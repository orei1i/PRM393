using System.Threading.Tasks;
using ApplicationLayer.DTOs.Media;
using Microsoft.AspNetCore.Http;

namespace ApplicationLayer.Interfaces
{
    public interface IMediaService
    {
        Task<UploadedImageResponse> UploadImageAsync(IFormFile file, string userId);
        Task<UploadedVideoResponse> UploadVideoAsync(IFormFile file, string userId);
        Task<bool> ValidateOwnerAsync(string mediaUrl, string userId);
    }
}
