using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

namespace OrdersService.Controllers
{
    public record CreateOrderRequest(string ProductId, int Quantity);

    public record Order(int Id, string ProductId, int Quantity, string Status, string ServedBy, DateTime CreatedAt);

    [ApiController]
    [Route("api/[controller]")]
    public class OrdersController : ControllerBase
    {
        private static readonly ConcurrentDictionary<int, Order> Orders = new();
        private static int _nextId;

        private readonly HttpClient _inventory;
        private readonly ILogger<OrdersController> _logger;

        public OrdersController(IHttpClientFactory httpClientFactory, ILogger<OrdersController> logger)
        {
            _inventory = httpClientFactory.CreateClient("inventory");
            _logger = logger;
        }

        // Exercise 7: the client only knows the logical name inventory-service.
        [HttpGet("inventory/{productId}")]
        public async Task<IActionResult> GetInventory(string productId)
        {
            var url = new Uri(_inventory.BaseAddress!, $"api/inventory/{productId}");
            try
            {
                var response = await _inventory.GetAsync(url);
                var content = await response.Content.ReadAsStringAsync();
                _logger.LogInformation("GET {Url} -> {Status} {Content}", url, (int)response.StatusCode, content);

                return StatusCode((int)response.StatusCode, new
                {
                    RequestedUrl = url.ToString(),
                    Inventory = JsonSerializer.Deserialize<JsonElement>(content),
                });
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                _logger.LogWarning("GET {Url} failed: {Error}", url, ex.Message);
                return StatusCode(StatusCodes.Status503ServiceUnavailable, new
                {
                    RequestedUrl = url.ToString(),
                    Error = $"Inventory service unreachable: {ex.Message}",
                });
            }
        }

        // Shows how the name is resolved from inside the container (Docker / Kubernetes DNS).
        [HttpGet("resolve")]
        public async Task<IActionResult> Resolve([FromQuery] string? host)
        {
            var name = host ?? _inventory.BaseAddress!.Host;
            try
            {
                var addresses = await Dns.GetHostAddressesAsync(name);
                return Ok(new { Name = name, Addresses = addresses.Select(a => a.ToString()) });
            }
            catch (Exception ex)
            {
                return NotFound(new { Name = name, Error = ex.Message });
            }
        }

        [HttpGet]
        public IActionResult GetAll() => Ok(Orders.Values.OrderBy(o => o.Id));

        [HttpPost]
        public async Task<IActionResult> Create(CreateOrderRequest request)
        {
            if (request.Quantity <= 0)
            {
                return BadRequest(new { Error = "Quantity must be greater than zero" });
            }

            HttpResponseMessage response;
            try
            {
                response = await _inventory.GetAsync($"api/inventory/{request.ProductId}");
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                return StatusCode(StatusCodes.Status503ServiceUnavailable, new { Error = $"Inventory service unreachable: {ex.Message}" });
            }

            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                return UnprocessableEntity(new { Error = $"Product {request.ProductId} does not exist" });
            }

            var stock = await response.Content.ReadFromJsonAsync<JsonElement>();
            var available = stock.GetProperty("stock").GetInt32();
            var servedBy = stock.GetProperty("server").GetString() ?? "unknown";

            if (available < request.Quantity)
            {
                return Conflict(new { Error = $"Not enough stock for {request.ProductId}", Available = available, ServedBy = servedBy });
            }

            var id = Interlocked.Increment(ref _nextId);
            var order = new Order(id, request.ProductId.ToUpperInvariant(), request.Quantity, "CONFIRMED", servedBy, DateTime.UtcNow);
            Orders[id] = order;

            return Created($"/api/orders/{id}", order);
        }
    }
}
