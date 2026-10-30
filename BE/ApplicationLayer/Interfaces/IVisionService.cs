using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Vision;
using Microsoft.AspNetCore.Http;

namespace ApplicationLayer.Interfaces
{
    public interface IVisionService
    {
        Task<ScanResultDto> ScanFridgeImageAsync(
            IFormFile image,
            string? currentUserId,
            CancellationToken ct = default);
    }
}

