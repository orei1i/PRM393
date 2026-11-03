using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.Interfaces
{
    public interface IPostService
    {
        Task<FeedPageResponse> GetFeedAsync(int page, int pageSize, string? type, string? mediaType, string? currentUserId, string? cursor = null, int? limit = null);
        Task<PostResponse> ModeratePostAsync(string postId, string actionOrDecision, string? reason = null);
        Task<FeedPageResponse> GetAdminPostsAsync(string? status, int page, int pageSize, string? search = null);
        Task<PostResponse> GetPostByIdAsync(string id, string? currentUserId, string? role = null);
        Task<PostResponse> CreatePostAsync(CreatePostRequest request, string currentUserId);
        Task<PostResponse> UpdatePostAsync(string id, CreatePostRequest request, string currentUserId);
        Task<bool> DeletePostAsync(string id, string currentUserId, string? role);
        Task<LikeResponse> ToggleLikeAsync(string postId, string currentUserId, string? role = null);
        Task<SaveResponse> ToggleSaveAsync(string postId, string currentUserId, string? role = null);
        Task<FeedPageResponse> GetMyPostsAsync(string currentUserId, string? status, string? cursor, int? limit);
        Task<IEnumerable<PostResponse>> GetSavedPostsAsync(string currentUserId);
        Task<bool> ReportPostAsync(string postId, string currentUserId, ReportPostRequest request, string? role = null);
    }
}
