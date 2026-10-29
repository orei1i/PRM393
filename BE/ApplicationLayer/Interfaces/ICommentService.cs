using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.Interfaces
{
    public interface ICommentService
    {
        Task<IEnumerable<CommentResponse>> GetPostCommentsAsync(string postId, int page, int pageSize);
        Task<CommentResponse> CreateCommentAsync(string postId, CreateCommentRequest request, string currentUserId);
        Task<bool> DeleteCommentAsync(string commentId, string currentUserId, string? role);
    }
}
