var builder = WebApplication.CreateBuilder(args);

// Logical name of the inventory service. It can be overridden with the
// environment variable Inventory__BaseUrl (e.g. to compare against a fixed IP).
var inventoryBaseUrl = builder.Configuration["Inventory:BaseUrl"] ?? "http://inventory-service:8080";

builder.Services.AddControllers();
builder.Services.AddHttpClient("inventory", client =>
{
    client.BaseAddress = new Uri(inventoryBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(3);
    // Do not reuse TCP connections: every request opens a new one, so the name is
    // resolved again and the requests are spread across all the instances
    // returned by the DNS (exercise 11).
    client.DefaultRequestHeaders.ConnectionClose = true;
});

var app = builder.Build();

app.MapControllers();
app.MapGet("/health", () => Results.Ok(new { Status = "UP", Server = Environment.MachineName }));

app.Logger.LogInformation("OrdersService will reach inventory at {InventoryBaseUrl}", inventoryBaseUrl);

app.Run();
