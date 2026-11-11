using System.Net;
using System.Net.Sockets;
using Microsoft.AspNetCore.Mvc;

namespace InventoryService.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class InventoryController : ControllerBase
    {
        private static readonly Dictionary<string, int> Stock = new(StringComparer.OrdinalIgnoreCase)
        {
            ["P001"] = 25,
            ["P002"] = 8,
            ["P003"] = 0,
        };

        // Container IP, so the client can see which address answered behind the logical name.
        private static readonly string Address = Dns.GetHostAddresses(Dns.GetHostName())
            .FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork)?.ToString() ?? "unknown";

        [HttpGet]
        public IActionResult GetAll()
        {
            return Ok(new
            {
                Products = Stock.Select(p => new { ProductId = p.Key, Stock = p.Value }),
                Server = Environment.MachineName,
                Address,
            });
        }

        [HttpGet("{productId}")]
        public IActionResult Get(string productId)
        {
            if (!Stock.TryGetValue(productId, out var stock))
            {
                return NotFound(new { Error = $"Product {productId} not found", Server = Environment.MachineName, Address });
            }

            return Ok(new
            {
                ProductId = productId.ToUpperInvariant(),
                Stock = stock,
                Server = Environment.MachineName,
                Address,
            });
        }
    }
}
