using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.Interfaces
{
    public interface IPostService
    {
        Task<FeedPageResponse> GetFeedAsync(int page, int pageSize, string? type, string? mediaType, string? currentUserId);
        Task<PostResponse> GetPostByIdAsync(string id, string? currentUserId);
        Task<PostResponse> CreatePostAsync(CreatePostRequest request, string currentUserId);
        Task<bool> DeletePostAsync(string id, string currentUserId, string? role);
        Task<LikeResponse> ToggleLikeAsync(string postId, string currentUserId);
        Task<bool> ReportPostAsync(string postId, string currentUserId, ReportPostRequest request);
    }
}
