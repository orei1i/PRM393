using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.Interfaces
{
    public interface ICommentService
    {
        Task<IEnumerable<CommentResponse>> GetPostCommentsAsync(string postId, int page, int pageSize, string? currentUserId = null, string? role = null);
        Task<CommentResponse> CreateCommentAsync(string postId, CreateCommentRequest request, string currentUserId, string? role = null);
        Task<CommentResponse> UpdateCommentAsync(string postId, string commentId, UpdateCommentRequest request, string currentUserId, string? role = null);
        Task<bool> DeleteCommentAsync(string commentId, string currentUserId, string? role);
        Task<IEnumerable<CommentResponse>> GetCommentRepliesAsync(string commentId, string? postId = null, string? currentUserId = null, string? role = null);
        Task<IEnumerable<MyCommentResponse>> GetMyCommentsAsync(string currentUserId);
        Task<IEnumerable<AdminCommentResponse>> GetAdminCommentsAsync(string? view, string? search, string? authorId, string? postId);
        Task<bool> AdminDeleteCommentAsync(string commentId, string? reason);
        Task<AdminCommentResponse> AdminActOnCommentAsync(string commentId, string action);
    }
}
