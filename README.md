# ShopResolver

Plataforma de comercio electrónico mínima para estudiar **nombrado en sistemas distribuidos**: un `OrdersService` que consulta a un `InventoryService` usando solo su nombre lógico (`http://inventory-service:8080`), nunca su dirección IP.

Caso práctico 4 — Sistemas Operativos / Sistemas Distribuidos (FCyT – UADER). Autor: Julián Olivera.

El informe en PDF con las respuestas y las salidas reales está en [`docs/Caso4_Nombrado_SD_Olivera.pdf`](docs/Caso4_Nombrado_SD_Olivera.pdf).

## Contenido

| Ruta | Qué hay |
|---|---|
| `InventoryService/` | Web API en C# (.NET 8). `GET /api/inventory/{productId}` devuelve el stock, el nombre del contenedor (`server`) y su IP (`address`). |
| `OrdersService/` | Web API en C# (.NET 8). Consulta a inventario por nombre con `HttpClient`. |
| `docker-compose.yml` | Ambos servicios en la red `ecommerce-network`. |
| `k8s/shopresolver.yaml` | El mismo sistema en Kubernetes: 3 Pods de inventario detrás de un `Service`. |
| `scripts/` | Un script por grupo de ejercicios; cada uno guarda su salida en `docs/salidas/`. |
| `docs/salidas/` | Salidas reales usadas como evidencia en este README y en el PDF. |
| `docs/generar_pdf.py` | Genera el PDF a partir de este README y de las salidas. |

## Requisitos

- Docker Desktop (o Docker Engine + Compose v2).
- Bash (en Windows sirve Git Bash) para los scripts.
- Solo para el ejercicio 13: [`kind`](https://kind.sigs.k8s.io/) y `kubectl`.
- No hace falta tener .NET instalado: las imágenes compilan con `mcr.microsoft.com/dotnet/sdk:8.0`.

## Ejecución rápida

```bash
docker compose up -d --build
curl http://localhost:8081/api/orders/inventory/P001
curl http://localhost:8081/api/orders/resolve
curl -X POST http://localhost:8081/api/orders -H "content-type: application/json" -d '{"productId":"P001","quantity":2}'
docker compose down
```

Endpoints de `OrdersService` (puerto 8081 del host):

| Método y ruta | Qué hace | Respuestas |
|---|---|---|
| `GET /api/orders/inventory/{productId}` | Llama a `http://inventory-service:8080/api/inventory/{productId}` y devuelve la URL usada y la respuesta | 200, 404, 503 si inventario no responde |
| `GET /api/orders/resolve?host=` | Resuelve un nombre desde dentro del contenedor (por defecto `inventory-service`) | 200, 404 |
| `POST /api/orders` | Crea un pedido si hay stock (`{"productId":"P001","quantity":2}`) | 201, 400, 409 sin stock, 422 producto inexistente, 503 |
| `GET /api/orders` | Lista los pedidos | 200 |

Productos precargados: `P001` (25), `P002` (8), `P003` (0).

La URL de inventario se toma de la variable `Inventory__BaseUrl` (por defecto `http://inventory-service:8080`). Así se puede comparar el nombre lógico contra una IP fija sin tocar el código (ejercicio 7).

Reproducir las evidencias:

```bash
bash scripts/ej01-05_docker_dns.sh   # red Docker, DNS embebido, cambio de IP, DNS de Internet
bash scripts/ej07-11_compose.sh      # C# en Compose, IP fija vs nombre, recreación, 3 instancias
bash scripts/ej13_kubernetes.sh      # Service de Kubernetes en un cluster kind
```

---

# Respuestas

## 1. Preguntas teóricas

### Nombre, identificador y dirección

Nombre: `inventory-service` — Dirección: `172.18.0.5`

**1. ¿Qué diferencia existe entre el nombre `inventory-service` y la dirección `172.18.0.5`?**
`inventory-service` es un nombre lógico, legible y estable que designa *qué* servicio se quiere usar. `172.18.0.5` es una dirección: indica *dónde* está, en ese momento, el punto de acceso (una interfaz de red de un contenedor concreto). El nombre se mantiene aunque el contenedor se recree; la dirección no: en la práctica, al recrear el contenedor pasó de `172.30.0.2` a `172.30.0.4` y el nombre siguió funcionando (ejercicio 4).

**2. ¿Qué se entiende por nombre dentro de un sistema distribuido?**
Una cadena de bits o caracteres que se usa para referirse a una entidad (un host, un servicio, un archivo, un usuario, un proceso). Los nombres “amigables” (*human-friendly*) están pensados para que los usen personas y programadores, y deben resolverse para poder acceder a la entidad.

**3. ¿Qué se entiende por identificador?**
Un nombre con tres propiedades (Tanenbaum y Van Steen): referencia a lo sumo a una entidad, cada entidad tiene a lo sumo un identificador y nunca se reutiliza para otra entidad, ni siquiera cuando la original deja de existir. Ejemplos: el ID del contenedor que asigna Docker (`d85808269c04…`), el UID de un Pod de Kubernetes, un UUID o una dirección MAC.

**4. ¿Qué se entiende por dirección?**
El nombre de un punto de acceso (*access point*) a una entidad: lo que se necesita para comunicarse con ella efectivamente, por ejemplo IP + puerto (`172.18.0.5:8080`). Una entidad puede tener varios puntos de acceso y estos pueden cambiar con el tiempo o ser reasignados a otra entidad.

**5. ¿Una dirección puede utilizarse como identificador? Justifique.**
En general no. Una dirección no cumple las propiedades de un identificador: puede cambiar aunque la entidad sea la misma (recrear el contenedor cambia la IP), puede reasignarse a otra entidad (en el ejercicio 7 la IP `172.29.0.2` que tenía inventario pasó a ser de otro contenedor, `filler`) y una entidad puede tener varias direcciones (un contenedor conectado a dos redes). Usarla como identificador lleva a referencias obsoletas o, peor, a hablar con la entidad equivocada.

**6. ¿Puede una misma entidad tener diferentes nombres? Proporcione un ejemplo.**
Sí, se llaman alias. En Docker el mismo contenedor responde a `inventory-service`, a su ID corto (`d85808269c04`, visible en `DNSNames`) y, en Compose, también a `shopresolver-inventory-service-1`. En Kubernetes el Service responde a `inventory-service`, `inventory-service.ecommerce` y `inventory-service.ecommerce.svc.cluster.local`. En DNS, un registro `CNAME` hace que `www.empresa.com` sea alias de `empresa.com`.

**7. ¿Puede un mismo nombre representar diferentes instancias de un servicio?**
Sí. El nombre identifica al servicio, no a la réplica. En el ejercicio 11, `inventory-service` resolvió a tres direcciones (`172.29.0.2`, `.4` y `.5`), una por instancia, y las consultas se repartieron entre ellas. Es la base del escalado horizontal y del balanceo de carga.

### Resolución de nombres

**1. ¿Qué significa resolver un nombre?**
Obtener, a partir del nombre, la información necesaria para acceder a la entidad: en general su dirección. Es una búsqueda en un servicio de nombres (DNS, el DNS embebido de Docker, CoreDNS en Kubernetes, un registro de servicios).

**2. ¿Qué componente transforma `inventory-service` en una dirección?**
El servidor DNS embebido de Docker, que escucha en `127.0.0.11` dentro de cada contenedor conectado a una red definida por el usuario (se ve en `/etc/resolv.conf`: `nameserver 127.0.0.11`). El resolver de la libc del contenedor le pregunta y Docker responde con la IP actual del contenedor llamado así. En Kubernetes ese rol lo cumple CoreDNS (`nameserver 10.96.0.10`).

**3. ¿Por qué conviene utilizar nombres en lugar de IP configuradas directamente?**
Porque desacopla al cliente de la ubicación del servidor: las IP las asigna dinámicamente la plataforma y cambian al recrear, reiniciar, mover o escalar. Con un nombre la configuración no cambia, es legible, permite tener varias instancias detrás y evita reconfigurar y redesplegar clientes. Con una IP fija, el `OrdersService` del ejercicio 7 quedó apuntando a una dirección obsoleta y devolvió 503.

**4. ¿Qué ocurre si `inventory-service` cambia su dirección IP?**
El DNS de Docker actualiza el registro automáticamente. La siguiente resolución devuelve la IP nueva y el cliente sigue funcionando sin modificaciones. Si el cliente hubiera guardado la IP vieja, sus pedidos fallarían (conexión rechazada o *timeout*) o llegarían a otro contenedor que heredó esa IP.

**5. ¿Qué relación existe entre resolución de nombres y transparencia de ubicación?**
La resolución de nombres es el mecanismo que hace posible la transparencia de ubicación: el cliente usa un nombre que no dice nada sobre dónde está el recurso, y la traducción a una dirección concreta ocurre en tiempo de ejecución, fuera del cliente. Si además el recurso puede moverse sin que el cliente lo note, se obtiene transparencia de migración/reubicación.

### Espacios de nombres

Considere: `api.inventory.empresa.com`

**1. ¿Qué es un espacio de nombres?**
El conjunto organizado de todos los nombres válidos de un sistema y las reglas para formarlos. Se representa como un grafo de nombres con nodos hoja (entidades) y nodos directorio (contextos que contienen otros nombres). Dentro de un mismo contexto un nombre es único.

**2. ¿Corresponde a un esquema plano o jerárquico?**
Jerárquico. El nombre está formado por etiquetas separadas por puntos, y cada una es un nivel de un árbol.

**3. Identifique los diferentes niveles del nombre.**
Se lee de derecha a izquierda, desde la raíz:

| Nivel | Etiqueta | Significado |
|---|---|---|
| 0 | `.` (implícito) | Raíz del DNS |
| 1 | `com` | Dominio de nivel superior (TLD) |
| 2 | `empresa` | Dominio de la organización (`empresa.com`) |
| 3 | `inventory` | Subdominio del área o sistema de inventario |
| 4 | `api` | Host / servicio concreto (`api.inventory.empresa.com`) |

**4. ¿Qué ventajas presenta un espacio de nombres jerárquico?**
- Unicidad global sin coordinación central: cada contexto solo garantiza que sus nombres sean únicos dentro de él.
- Delegación de autoridad: `empresa` administra todo lo que cuelga de `empresa.com`.
- Escalabilidad: la base de datos se reparte en zonas y servidores.
- Resolución eficiente por partes (iterativa o recursiva) y caché por niveles.
- Nombres legibles que reflejan la organización.

**5. ¿Por qué DNS utiliza una estructura jerárquica?**
Porque tiene que nombrar cientos de millones de hosts administrados por organizaciones independientes. La jerarquía permite partir el espacio en zonas, delegar cada zona a quien la administra, distribuir la carga entre muchos servidores y cachear las respuestas de los niveles altos (que casi no cambian). Un espacio plano necesitaría una autoridad única y no escalaría.

### DNS

**1. ¿Qué función cumple DNS?**
Es el servicio de nombres de Internet: traduce nombres de dominio a información asociada, sobre todo direcciones IP (registros `A`/`AAAA`), pero también servidores de correo (`MX`), alias (`CNAME`), servidores de nombres (`NS`) y texto (`TXT`).

**2. ¿Por qué DNS puede considerarse un sistema distribuido?**
Porque su base de datos está repartida entre millones de servidores autónomos de distintas organizaciones (raíz, TLD, autoritativos, recursivos), que cooperan mediante un protocolo común para resolver cualquier nombre, con replicación (servidores primarios y secundarios, *anycast*), caché en todos los niveles y sin un punto central que conozca todo. Para el usuario se comporta como un único servicio.

**3. ¿Qué información almacena un servidor DNS?**
Registros de recursos (*resource records*) de las zonas de las que es autoridad: `SOA`, `NS`, `A`, `AAAA`, `CNAME`, `MX`, `PTR`, `TXT`, `SRV`, cada uno con su TTL. Un servidor recursivo, además, guarda en caché respuestas obtenidas de otros servidores mientras dure su TTL.

**4. ¿Qué diferencia existe entre un nombre de dominio y una dirección IP?**
El nombre de dominio es un identificador lógico, jerárquico y legible (`www.google.com`) que no depende de la red física. La IP es la dirección numérica que usa la capa de red para enrutar paquetes. Un nombre puede apuntar a muchas IP (en el ejercicio 5, `www.google.com` devolvió 8 direcciones IPv4 y 8 IPv6) y las IP de un nombre pueden cambiar sin cambiar el nombre.

**5. ¿Qué ventajas proporciona el uso de caché?**
Menor latencia (la respuesta está cerca), menos carga sobre servidores raíz, TLD y autoritativos, menos tráfico en la red y cierta tolerancia a fallas temporales de los servidores autoritativos. El costo es la consistencia: un cambio puede tardar hasta el TTL en verse (por eso Docker usa un TTL de 600 s pero responde siempre con su estado actual, y Google usa TTL de 300 s).

**6. ¿Qué ocurriría si las aplicaciones tuvieran que conocer directamente las IP de todos los servicios?**
Cada cambio de dirección (migración, reinicio, cambio de proveedor, escalado, falla) obligaría a reconfigurar y redistribuir todas las aplicaciones. Habría configuraciones desactualizadas, errores, imposibilidad de balancear carga o de mover servicios sin cortes, y un acoplamiento total entre clientes e infraestructura. En la práctica, Internet y cualquier sistema dinámico serían inmanejables.

### Nombrado en arquitecturas modernas

**1. ¿Por qué resulta inconveniente configurar manualmente las IP de los microservicios?**
Porque en microservicios las instancias son efímeras: se crean, destruyen, reinician y escalan constantemente y la plataforma les asigna IP dinámicas. Una IP configurada a mano queda obsoleta en el primer redespliegue, no admite varias réplicas, no se adapta a fallas y obliga a coordinar cambios de configuración entre equipos.

**2. ¿Qué ocurre cuando un contenedor es eliminado y creado nuevamente?**
Es un contenedor nuevo: recibe otro ID y, en general, otra dirección IP (la que el IPAM de Docker tenga libre). Lo único que se conserva es el nombre, porque se vuelve a crear con el mismo `--name` o porque Compose usa el mismo nombre de servicio. En el ejercicio 4 la IP pasó de `172.30.0.2` a `172.30.0.4`.

**3. ¿Por qué un nombre puede permanecer estable aunque cambie la dirección?**
Porque el nombre y la dirección están desacoplados por una tabla de asociación (*binding*) que mantiene el servicio de nombres. Cuando la entidad cambia de ubicación solo se actualiza esa asociación; el nombre, que es lo que conocen los clientes, no cambia.

**4. ¿Qué se entiende por Service Discovery?**
El mecanismo por el cual un cliente encuentra, en tiempo de ejecución, las instancias disponibles de un servicio a partir de su nombre lógico. Incluye un registro (*service registry*) con las instancias vivas, la forma en que estas se registran y dan de baja, controles de salud y la consulta (por DNS o por API). Ejemplos: DNS embebido de Docker, Services + CoreDNS de Kubernetes, Consul, Eureka.

**5. ¿Qué relación existe entre Service Discovery y nombrado?**
Service Discovery es un servicio de nombres especializado para entornos dinámicos: resuelve un nombre lógico de servicio a un conjunto de direcciones de instancias sanas que cambia constantemente. El nombre es la clave de búsqueda; el registro es el espacio de nombres.

**6. ¿Qué diferencias existen entre DNS tradicional y descubrimiento de servicios?**

| Aspecto | DNS tradicional | Service Discovery |
|---|---|---|
| Dinamismo | Registros relativamente estables, cambios manuales o poco frecuentes | Instancias que aparecen y desaparecen todo el tiempo, registro automático |
| Caché / TTL | TTL de minutos u horas, propagación lenta | TTL cortos o nulos, información casi en tiempo real |
| Salud | No sabe si el host responde | Health checks: solo devuelve instancias sanas |
| Información | Nombre → IP (y algunos registros extra) | Nombre → instancias con IP, puerto, versión, metadatos |
| Balanceo | Round-robin básico | Balanceo del lado del cliente o del servidor (proxy, ClusterIP) |
| Alcance | Global, jerárquico, multi-organización | Interno a un cluster o plataforma |

---

## 2. Ejercicios

Caso: `orders-service` usaba `http://172.18.0.5:8080/api/inventory`; al recrear el contenedor, inventario recibió `172.18.0.9` y el pedido se rompió. La propuesta es usar `http://inventory-service:8080/api/inventory`. Los ejercicios lo comprueban.

> Las IP de las salidas son de las redes que creó Docker en mi máquina (`172.30.0.0/16` en los ejercicios 1 a 5 y `172.29.0.0/16` con Compose); en otra máquina pueden ser `172.18.x.x` u otras. Las salidas completas están en `docs/salidas/`.

### Ejercicio 1 — Crear una red Docker

```text
$ docker network create ecommerce-network
$ docker network ls --filter name=ecommerce-network
NETWORK ID     NAME                DRIVER    SCOPE
37ddea68d0dc   ecommerce-network   bridge    local
$ docker network inspect ecommerce-network
Name=ecommerce-network Driver=bridge Subnet=172.30.0.0/16 Gateway=172.30.0.1
```

1. **¿Qué función cumple una red Docker?** Crea una red virtual aislada (un *bridge* de Linux con su subred, `172.30.0.0/16`, y gateway `172.30.0.1`) que conecta contenedores entre sí, les asigna IP por IPAM y los aísla de los contenedores de otras redes.
2. **¿Qué servicios pueden comunicarse en ella?** Solo los contenedores conectados a esa red (`--network ecommerce-network` o `docker network connect`). Un contenedor en la red `bridge` por defecto o en otra red no puede alcanzarlos por nombre ni, salvo configuración, por IP.
3. **¿Qué relación tiene con la resolución de nombres?** En las redes definidas por el usuario Docker activa su DNS embebido (`127.0.0.11`): cada contenedor puede resolver a los demás por su nombre, sus alias o su nombre de servicio. La red es el ámbito (contexto) del espacio de nombres; en la red `bridge` por defecto esto no ocurre y habría que usar IP o el obsoleto `--link`.

### Ejercicio 2 — Crear el servicio de inventario

```text
$ docker run -d --name inventory-service --network ecommerce-network nginx
$ docker ps
NAMES               IMAGE     STATUS
inventory-service   nginx     Up Less than a second
$ docker inspect inventory-service
Name=/inventory-service State=running Networks=ecommerce-network IP=172.30.0.2
MAC=f2:2d:e0:e9:c2:d6 DNSNames=[inventory-service d85808269c04]
```

| Dato | Valor |
|---|---|
| Nombre | `inventory-service` |
| IP | `172.30.0.2` |
| Red | `ecommerce-network` |
| Estado | `running` |
| Identificador | `d85808269c04…` (ID del contenedor) |

**Diferencia entre nombre y dirección:** el nombre lo eligió quien lanzó el contenedor y significa algo (“el servicio de inventario”); la IP la asignó Docker automáticamente y solo sirve para enrutar. Los `DNSNames` muestran que el contenedor tiene dos nombres resolubles: el nombre y su ID corto, que es un identificador.

### Ejercicio 3 — Crear un cliente

El PDF usa `docker run -it ... alpine`; el script usa `-d alpine sleep infinity` y `docker exec` para poder automatizarlo. El resultado es el mismo.

```text
$ cat /etc/resolv.conf
nameserver 127.0.0.11
$ ping -c 3 inventory-service
PING inventory-service (172.30.0.2): 56 data bytes
64 bytes from 172.30.0.2: seq=0 ttl=64 time=0.066 ms
$ nslookup inventory-service
Server:		127.0.0.11
Address:	127.0.0.11#53
Name:	inventory-service
Address: 172.30.0.2
$ getent hosts inventory-service
172.30.0.2        inventory-service  inventory-service
$ curl http://inventory-service
HTTP 200 desde 172.30.0.2
```

- **¿Quién resolvió el nombre?** El DNS embebido de Docker en `127.0.0.11` (lo indica `Server: 127.0.0.11` y el `resolv.conf` que Docker genera). `getent hosts` muestra que la resolución pasa por la libc del sistema (NSS), que es lo mismo que usa cualquier aplicación.
- **¿Fue necesario conocer la IP?** No. En ningún comando se escribió `172.30.0.2`; se obtuvo a partir del nombre.
- **¿Qué ventaja presenta?** El cliente se configura una sola vez con el nombre; la IP puede cambiar, el servicio se puede recrear o escalar y el cliente sigue funcionando. Además es legible y no depende de la subred de cada máquina.

### Ejercicio 4 — Cambio de dirección

Para reproducir el caso del enunciado (`172.18.0.5` → `172.18.0.9`) se lanza un contenedor `filler` antes de recrear inventario: ocupa la IP liberada y obliga a Docker a asignar otra. Sin él, Docker puede devolver la misma IP porque es la primera libre; eso no cambia la conclusión, la IP sigue siendo algo que el cliente no controla.

```text
IP de inventory-service ANTES: 172.30.0.2
$ docker stop inventory-service && docker rm inventory-service
$ docker run -d --name filler --network ecommerce-network alpine sleep infinity
$ docker run -d --name inventory-service --network ecommerce-network nginx
IP de inventory-service DESPUES: 172.30.0.4
IP de filler (ocupa la direccion anterior): 172.30.0.2
$ nslookup inventory-service          (desde orders-service)
Name:	inventory-service
Address: 172.30.0.4
$ curl http://inventory-service
HTTP 200 desde 172.30.0.4
$ curl http://172.30.0.2
HTTP 000 -> La IP vieja 172.30.0.2 ya no corresponde a inventory-service
```

1. **¿Cambió la IP?** Sí: de `172.30.0.2` a `172.30.0.4`.
2. **¿Cambió el nombre?** No, sigue siendo `inventory-service`.
3. **¿Fue necesario modificar el cliente?** No. `orders-service` ni se reinició: la siguiente consulta DNS ya devolvió la IP nueva. Quien hubiera usado la IP vieja ahora le habla a `filler`, que ni siquiera es un servidor web.
4. **¿Qué relación tiene con transparencia de ubicación?** Es exactamente eso: el recurso cambió de ubicación y el cliente no se enteró, porque solo conoce el nombre y la plataforma mantiene actualizada la asociación nombre → dirección (transparencia de ubicación y de reubicación).

### Ejercicio 5 — DNS tradicional

```text
$ nslookup www.google.com
Server:		127.0.0.11
Non-authoritative answer:
Name:	www.google.com   Address: 142.251.157.119
...  (8 direcciones IPv4 y 8 IPv6)
$ dig +noall +answer +stats www.google.com
www.google.com.		299	IN	A	142.251.157.119
...
;; Query time: 4 msec
;; SERVER: 127.0.0.11#53(127.0.0.11) (UDP)
$ dig +noall +answer inventory-service
inventory-service.	600	IN	A	172.30.0.4
$ dig @8.8.8.8 inventory-service
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN
```

| Aspecto | DNS de Internet | DNS interno de Docker |
|---|---|---|
| Quién responde | Jerarquía raíz → `.com` → `google.com` (autoritativo), vía resolvers recursivos con caché | El daemon de Docker en `127.0.0.11`, que conoce los contenedores de la red |
| Espacio de nombres | Jerárquico y global (`www.google.com.`) | Plano y local a la red (`inventory-service`) |
| Respuesta | `Non-authoritative answer`: la da un resolver recursivo con caché, no el servidor autoritativo de `google.com`; TTL 300 s | Autoritativa para la red; TTL 600 s pero siempre con el estado actual |
| Alcance | Cualquier host de Internet | Solo contenedores de `ecommerce-network`; `8.8.8.8` responde `NXDOMAIN` para `inventory-service` |
| Varias IP | Sí, para repartir carga y por redundancia | Sí, cuando hay varias instancias del servicio (ejercicio 11) |

El DNS embebido hace de *forwarder*: lo que no conoce (`www.google.com`) lo reenvía al DNS del host. Por eso un mismo resolver sirve para nombres internos y externos.

### Ejercicio 6 — InventoryService en C#

Se creó la Web API con controladores (`InventoryService/`). Se partió del controlador del enunciado y se agregó un pequeño catálogo y el campo `address` (IP del contenedor) para ver qué instancia atiende cada pedido:

```csharp
[HttpGet("{productId}")]
public IActionResult Get(string productId)
{
    if (!Stock.TryGetValue(productId, out var stock))
        return NotFound(new { Error = $"Product {productId} not found", Server = Environment.MachineName, Address });

    return Ok(new { ProductId = productId.ToUpperInvariant(), Stock = stock,
                    Server = Environment.MachineName, Address });
}
```

`Environment.MachineName` dentro de un contenedor es su *hostname*, que Docker inicializa con el ID corto del contenedor: un identificador, no un nombre lógico. Por eso en las salidas aparece `server: "86ef2a49f6a5"` mientras que el cliente usa `inventory-service`.

Se ejecuta con `dotnet run` (local) o, como en este repo, dentro de Docker (ejercicio 8).

### Ejercicio 7 — OrdersService

`OrdersService/` usa el nombre lógico. En vez de `new HttpClient()` se usa `IHttpClientFactory` (evita agotar sockets) y la URL base viene de configuración:

```csharp
var inventoryBaseUrl = builder.Configuration["Inventory:BaseUrl"] ?? "http://inventory-service:8080";
builder.Services.AddHttpClient("inventory", client => { client.BaseAddress = new Uri(inventoryBaseUrl); ... });

// OrdersController
var response = await _inventory.GetAsync($"api/inventory/{productId}");
var content = await response.Content.ReadAsStringAsync();
_logger.LogInformation("GET {Url} -> {Status} {Content}", url, (int)response.StatusCode, content);
```

**Comparación IP directa vs nombre lógico.** Se levantaron dos `OrdersService` idénticos: el de Compose con `http://inventory-service:8080` y otro (`orders-by-ip`, puerto 8082) con la IP que tenía inventario en ese momento, `http://172.29.0.2:8080`. Luego se recreó inventario:

```text
--- Con ambas configuraciones funcionando ---
:8081 {"requestedUrl":"http://inventory-service:8080/api/inventory/P001","inventory":{"stock":25,"server":"86ef2a49f6a5","address":"172.29.0.2"}}
:8082 {"requestedUrl":"http://172.29.0.2:8080/api/inventory/P001","inventory":{"stock":25,"server":"86ef2a49f6a5","address":"172.29.0.2"}}

--- Se recrea inventory-service ---
IP vieja: 172.29.0.2  |  IP nueva: 172.29.0.5  |  filler: 172.29.0.2

:8081 {"requestedUrl":"http://inventory-service:8080/api/inventory/P001","inventory":{"stock":25,"server":"756d8558c4b8","address":"172.29.0.5"}} [HTTP 200]
:8082 {"requestedUrl":"http://172.29.0.2:8080/api/inventory/P001","error":"Inventory service unreachable: Connection refused (172.29.0.2:8080)"} [HTTP 503]
```

| | IP directa | Nombre lógico |
|---|---|---|
| Antes de recrear | Funciona | Funciona |
| Después de recrear | 503: la IP ahora es de otro contenedor | Funciona; habla con la instancia nueva |
| Para arreglarlo | Buscar la IP nueva, cambiar la configuración y reiniciar el cliente | Nada |
| Varias instancias | Imposible con una sola IP | El nombre resuelve a todas |

### Ejercicio 8 — Dockerizar los servicios

`InventoryService/Dockerfile` es el del enunciado. El de `OrdersService` es el equivalente (compilación en `sdk:8.0`, ejecución en `aspnet:8.0`):

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "OrdersService.dll"]
```

La imagen `aspnet:8.0` escucha por defecto en el puerto 8080 (`ASPNETCORE_HTTP_PORTS=8080`), por eso la URL es `inventory-service:8080`. Cada proyecto tiene un `.dockerignore` que excluye `bin/` y `obj/`.

### Ejercicio 9 — Docker Compose

`docker-compose.yml` es el del enunciado con tres agregados: la variable `Inventory__BaseUrl`, el puerto `8081:8080` de orders para probarlo desde el host, y ningún `container_name` ni puerto publicado en inventario, para poder escalarlo (ejercicio 11).

```text
$ docker compose up -d --build
$ docker compose ps
NAME                               SERVICE             STATUS     PORTS
shopresolver-inventory-service-1   inventory-service   Up
shopresolver-orders-service-1      orders-service      Up         0.0.0.0:8081->8080/tcp
$ docker network ls --filter name=ecommerce
0ea1bea35f65   shopresolver_ecommerce-network   bridge    local
Direcciones: inventory-service-1 172.29.0.2 | orders-service-1 172.29.0.3

$ curl localhost:8081/api/orders/resolve
{"name":"inventory-service","addresses":["172.29.0.2"]}
$ curl localhost:8081/api/orders/inventory/P001
{"requestedUrl":"http://inventory-service:8080/api/inventory/P001","inventory":{"productId":"P001","stock":25,"server":"86ef2a49f6a5","address":"172.29.0.2"}}
$ curl -X POST localhost:8081/api/orders -d '{"productId":"P001","quantity":2}'
{"id":1,"productId":"P001","quantity":2,"status":"CONFIRMED","servedBy":"86ef2a49f6a5",...}
$ curl -X POST localhost:8081/api/orders -d '{"productId":"P003","quantity":1}'
{"error":"Not enough stock for P003","available":0,"servedBy":"86ef2a49f6a5"} [HTTP 409]
```

**Nombres, direcciones y resolución en Compose:**
- Compose crea la red con el prefijo del proyecto (`shopresolver_ecommerce-network`) y los contenedores con nombre `<proyecto>-<servicio>-<n>`.
- Además registra el **nombre del servicio** (`inventory-service`) como alias DNS de todos sus contenedores. Ese es el nombre lógico que usa el cliente; el nombre del contenedor es un detalle de implementación.
- Las IP (`.2`, `.3`) las asigna Docker en orden de creación; nadie las configuró.
- `depends_on` solo ordena el arranque; no tiene que ver con la resolución.

### Ejercicio 10 — Recrear la infraestructura

```text
--- ANTES ---
/shopresolver-inventory-service-1 172.29.0.5
/shopresolver-orders-service-1 172.29.0.3
$ docker compose down     # borra contenedores y red
$ docker compose up -d
--- DESPUES ---
/shopresolver-inventory-service-1 172.29.0.2
/shopresolver-orders-service-1 172.29.0.3
$ curl localhost:8081/api/orders/resolve
{"name":"inventory-service","addresses":["172.29.0.2"]}
$ curl localhost:8081/api/orders/inventory/P002
{"requestedUrl":"http://inventory-service:8080/api/inventory/P002","inventory":{"productId":"P002","stock":8,"server":"ad38a4435513","address":"172.29.0.2"}}
```

Los contenedores son nuevos (otro ID, `server` distinto) e inventario cambió de `172.29.0.5` a `172.29.0.2`. **El cliente no necesitó ninguna modificación**: la imagen y la configuración de `OrdersService` son las mismas y siguen apuntando a `inventory-service:8080`. Vale notar que tras un `down`/`up` limpio las IP suelen repetirse (Docker reparte en orden de creación sobre una red nueva), pero no hay ninguna garantía de eso: depende del orden de arranque, de otros contenedores en la red y de la subred que asigne Docker. Por eso el cliente no debe depender de ellas.

### Ejercicio 11 — Múltiples instancias

```text
$ docker compose up -d --scale inventory-service=3
inventory-service-1 172.29.0.2 | inventory-service-2 172.29.0.5 | inventory-service-3 172.29.0.4
$ curl localhost:8081/api/orders/resolve
{"name":"inventory-service","addresses":["172.29.0.4","172.29.0.2","172.29.0.5"]}
```

```text
--- 12 consultas a http://inventory-service:8080 (server = contenedor que respondió) ---
ad38a4435513 172.29.0.2
080514710eca 172.29.0.5
cfcb185bd2ad 172.29.0.4
ad38a4435513 172.29.0.2
...
--- Reparto de 30 consultas ---
     10 172.29.0.2
     16 172.29.0.4
      4 172.29.0.5
--- Falla una instancia (docker stop inventory-service-1, 172.29.0.2) ---
$ curl localhost:8081/api/orders/resolve
{"name":"inventory-service","addresses":["172.29.0.4","172.29.0.5"]}
     18 172.29.0.4 HTTP 200
     12 172.29.0.5 HTTP 200
```

1. **¿Debería OrdersService conocer las tres IP?** No. Debe conocer un único nombre, `inventory-service`; cuántas instancias hay y dónde están es responsabilidad de la plataforma.
2. **¿Qué problemas generaría?** Configuración que cambia con cada escalado o reinicio; el cliente tendría que implementar su propio balanceo, detectar caídas y reintentar; habría que redesplegarlo para agregar o quitar instancias; las IP obsoletas producen errores o tráfico hacia contenedores equivocados; y se acoplan equipos e infraestructura.
3. **¿Qué mecanismo debería localizar las instancias?** Un servicio de nombres / Service Discovery: aquí el DNS embebido de Docker, que devuelve un registro `A` por cada contenedor del servicio. En Kubernetes, el Service con CoreDNS; en otras plataformas, Consul, Eureka o un balanceador.
4. **¿Cómo se relaciona con balanceo de carga?** El DNS de Docker hace *round-robin DNS*: devuelve las direcciones en distinto orden y cada cliente usa la primera, así la carga se reparte. Para que se note, `OrdersService` abre una conexión nueva por pedido (`ConnectionClose = true`) y entonces resuelve el nombre cada vez; con conexiones persistentes, el cliente se quedaría “pegado” a una instancia. Es un balanceo simple: no sabe de carga ni de salud. En Kubernetes el balanceo lo hace el Service (kube-proxy) detrás de una única IP virtual.
5. **¿Qué ocurre si una instancia falla?** Al detenerse el contenedor, Docker lo quita del DNS: el nombre pasa a resolver solo a las dos instancias restantes y todos los pedidos siguieron respondiendo 200, sin tocar el cliente. Límites: Docker solo lo detecta si el contenedor se detiene (un proceso colgado pero vivo seguiría en el DNS) y las conexiones en curso hacia la instancia caída fallan; por eso en producción se agregan *health checks* y reintentos.

### Ejercicio 12 — Service Discovery

1. **¿Qué información mantiene Service Discovery?** Un registro con, por cada nombre lógico de servicio, la lista de instancias disponibles: dirección IP, puerto, estado de salud, y a veces metadatos (versión, zona, pesos, etiquetas) y la fecha del último *heartbeat*.
2. **¿Cómo se registran nuevas instancias?** De dos formas. *Auto-registro*: la instancia, al arrancar, se anota en el registro (Eureka, Consul agent). *Registro por terceros*: la plataforma lo hace sola, que es lo que pasa en Docker (al conectar el contenedor a la red se agrega su nombre y alias) y en Kubernetes (el controlador de EndpointSlices agrega cada Pod que coincide con el `selector` del Service y está *Ready*).
3. **¿Cómo se detectan instancias no disponibles?** Con *health checks* activos (el registro o la plataforma consultan un endpoint como `/health`; en Kubernetes, la `readinessProbe`), con *heartbeats* y TTL (si la instancia deja de renovar su registro, vence) o por eventos del orquestador (contenedor detenido, Pod eliminado). Las instancias que fallan se quitan de las respuestas.
4. **¿Qué relación existe con nombrado?** Service Discovery *es* resolución de nombres aplicada a servicios dinámicos: el cliente entrega un nombre lógico y recibe direcciones. Agrega a un servicio de nombres clásico el registro automático, la salud y la actualización casi en tiempo real.
5. **¿Por qué es importante en microservicios?** Porque hay muchos servicios, con muchas réplicas efímeras, IP dinámicas y escalado automático. Sin descubrimiento habría que mantener a mano qué instancia está dónde, algo imposible a esa escala. Con él se logran transparencia de ubicación, escalado horizontal, tolerancia a fallas y despliegues sin cortes.

### Ejercicio 13 — Kubernetes

`k8s/shopresolver.yaml` despliega el mismo sistema en Kubernetes: un `Deployment` de inventario con 3 réplicas y `readinessProbe` sobre `/health`, un `Service` `inventory-service` (ClusterIP) delante, y `OrdersService` sin ningún cambio, con `Inventory__BaseUrl=http://inventory-service:8080`. El script `scripts/ej13_kubernetes.sh` lo ejecuta en un cluster local de [kind](https://kind.sigs.k8s.io/) (en la salida, `k` es `kubectl -n ecommerce`).

```text
$ kubectl get pods -o wide
inventory-service-694dddbb9f-krtgg   1/1  Running  10.244.0.6
inventory-service-694dddbb9f-mb422   1/1  Running  10.244.0.7
inventory-service-694dddbb9f-rwjpw   1/1  Running  10.244.0.5
orders-service-749959f4bd-xjnz6      1/1  Running  10.244.0.8
$ kubectl get service
inventory-service   ClusterIP   10.96.136.163   8080/TCP
orders-service      NodePort    10.96.122.92    8080:30081/TCP
$ kubectl get endpointslices -l kubernetes.io/service-name=inventory-service
inventory-service-kq6v8   IPv4   8080   10.244.0.6,10.244.0.7,10.244.0.5
$ cat /etc/resolv.conf                      (dentro de un Pod)
search ecommerce.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
$ nslookup inventory-service.ecommerce.svc.cluster.local
Server:   10.96.0.10
Address:  10.96.136.163
$ wget -qO- http://orders-service:8080/api/orders/resolve
{"name":"inventory-service","addresses":["10.96.136.163"]}

--- 30 consultas: el Service reparte entre los Pods ---
     13 inventory-service-694dddbb9f-krtgg 10.244.0.6
      6 inventory-service-694dddbb9f-mb422 10.244.0.7
     11 inventory-service-694dddbb9f-rwjpw 10.244.0.5

$ kubectl delete pod inventory-service-694dddbb9f-krtgg
$ kubectl get pods -l app=inventory-service -o wide
inventory-service-694dddbb9f-kwfvb   1/1  Running  10.244.0.10    <- Pod nuevo, IP nueva
inventory-service-694dddbb9f-mb422   1/1  Running  10.244.0.7
inventory-service-694dddbb9f-rwjpw   1/1  Running  10.244.0.5
$ kubectl get endpointslices ...
inventory-service-kq6v8   IPv4   8080   10.244.0.7,10.244.0.5,10.244.0.10
$ kubectl get service inventory-service
inventory-service   ClusterIP   10.96.136.163   8080/TCP       <- no cambió

      9 inventory-service-694dddbb9f-kwfvb 10.244.0.10
     10 inventory-service-694dddbb9f-mb422 10.244.0.7
     11 inventory-service-694dddbb9f-rwjpw 10.244.0.5
```

1. **¿Qué problema de nombrado resuelve Kubernetes Service?** Da un nombre y una dirección **estables** a un conjunto de Pods efímeros. El `Service` `inventory-service` tiene un nombre DNS (`inventory-service.ecommerce.svc.cluster.local`, resuelto por CoreDNS) y una IP virtual (`10.96.136.163`) que no cambian mientras el Service exista, aunque los Pods de detrás se creen, mueran o se multipliquen. Además selecciona los Pods por etiquetas (`app: inventory-service`), no por dirección, y reparte el tráfico entre ellos.
2. **¿Por qué no conviene referenciar directamente las IP de los Pods?** Porque los Pods son desechables: cada vez que se recrean (falla, despliegue de una versión nueva, reprogramación en otro nodo, escalado) reciben otra IP del rango del cluster. En la práctica, el Pod `…krtgg` (`10.244.0.6`) fue reemplazado por `…kwfvb` (`10.244.0.10`): una referencia a `10.244.0.6` habría quedado rota. Tampoco permitiría repartir carga entre réplicas ni excluir Pods que no están listos.
3. **¿Qué ocurre si un Pod es reemplazado?** El `Deployment` (vía su ReplicaSet) crea uno nuevo para mantener 3 réplicas; el nuevo tiene otro nombre e IP. El controlador de EndpointSlices quita la IP vieja y agrega la nueva cuando el Pod pasa la `readinessProbe`. El Service conserva su nombre y su ClusterIP, y las consultas siguieron repartiéndose entre los 3 Pods actuales.
4. **¿El cliente necesita conocer el cambio?** No. `OrdersService` resuelve `inventory-service` y obtiene siempre la misma ClusterIP; kube-proxy traduce esa IP virtual a la IP de algún Pod listo. El cliente nunca ve las IP de los Pods: ni siquiera tiene que volver a resolver el nombre.
5. **¿Cómo se relaciona con transparencia de ubicación?** Es transparencia de ubicación, migración y replicación al mismo tiempo: el cliente usa un nombre que no dice en qué nodo ni en qué Pod corre el servicio, cuántas réplicas hay ni si fueron reemplazadas. A diferencia de Docker, donde el nombre resuelve directamente a las IP de los contenedores, en Kubernetes hay una indirección más (nombre → IP virtual del Service → Pod), que oculta incluso los cambios de dirección.

### Ejercicio 14 — Comparación

| Mecanismo | Nombre utilizado | Quién resuelve | Destino | ¿Puede cambiar la IP? |
|---|---|---|---|---|
| DNS Internet | `www.ejemplo.com` | Jerarquía DNS (resolver recursivo → raíz → TLD → autoritativo), con caché | Servidor(es) | Sí, y el cliente lo ve cuando vence el TTL |
| Docker | `inventory-service` | DNS embebido de Docker (`127.0.0.11`) | Contenedor(es) del servicio, una IP por instancia | Sí, en cada recreación; el DNS se actualiza al instante |
| Kubernetes | `inventory-service` (`.ecommerce.svc.cluster.local`) | CoreDNS → ClusterIP del Service → kube-proxy elige un Pod | Pods detrás del Service | Las IP de los Pods sí; la ClusterIP del Service no cambia mientras exista |
| IP directa | `172.18.0.5` | No existe resolución | Host / contenedor que tenga esa IP hoy | La referencia queda obsoleta y puede apuntar a otra entidad |

Observado en este trabajo: Docker devolvió una IP distinta por instancia y el cliente reparte resolviendo cada vez; Kubernetes devolvió siempre una sola IP virtual estable y repartió por detrás; la IP directa terminó en 503.

### Ejercicio 15 — Conclusión

```text
NOMBRE  ──resolución──▶  DIRECCIÓN  ──acceso──▶  ENTIDAD / SERVICIO
inventory-service   DNS de Docker / CoreDNS   172.29.0.4:8080 (hoy)   contenedor o Pod de inventario
```

En un sistema distribuido conviene separar tres cosas: **qué** se quiere usar (el nombre), **dónde** está ahora (la dirección) y **quién** es concretamente (la entidad, con su identificador). La **resolución** es la función que, en el momento del acceso, conecta el nombre con la dirección vigente.

Los componentes de un sistema distribuido moderno cambian todo el tiempo: los contenedores se recrean y reciben otra IP (ejercicios 4 y 10), se escalan a varias instancias (ejercicio 11), fallan y son reemplazados (ejercicios 11 y 13) o se mueven de nodo. Si el cliente guardara direcciones, cada uno de esos eventos lo rompería, como le pasó al `OrdersService` configurado con `172.29.0.2`, que terminó en 503 mientras el que usaba el nombre siguió respondiendo.

Al depender solo del nombre, el cliente queda desacoplado de la ubicación física: la plataforma (DNS de Internet, DNS embebido de Docker, Service y CoreDNS de Kubernetes, o un registro de Service Discovery) se encarga de mantener la asociación nombre → direcciones al día, solo con instancias vivas, y de repartir la carga. Eso es lo que da **transparencia de ubicación, de migración y de replicación**, permite **escalar horizontalmente** y **tolerar fallas** sin modificar ni redesplegar los clientes. Por eso los nombres no son un detalle de configuración sino una pieza central de la arquitectura de cualquier sistema distribuido.

## Bibliografía

1. Tanenbaum, A. S. y Van Steen, M. *Distributed Systems*, cap. 6 “Naming”.
2. Coulouris, G., Dollimore, J., Kindberg, T. y Blair, G. *Distributed Systems: Concepts and Design*. Pearson, cap. “Name services”.
3. Docker Docs — *Networking overview* y *Container networking / DNS services*.
4. Microsoft Learn — *ASP.NET Core Web API*, *IHttpClientFactory*, *Containerize a .NET app*.
5. Kubernetes Docs — *Service*, *DNS for Services and Pods*, *EndpointSlices*.
