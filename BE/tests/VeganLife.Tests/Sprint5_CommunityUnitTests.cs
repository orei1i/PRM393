using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using ApplicationLayer.Services;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint5_CommunityUnitTests
    {
        [Fact]
        public async Task B15_FeedCursorPagination_InvalidCursorThrowsBadRequest()
        {
            var mockPostRepo = new Mock<IGenericRepository<Post>>();
            var mockUserRepo = new Mock<IGenericRepository<User>>();
            var mockLikeRepo = new Mock<IGenericRepository<PostLike>>();
            var mockReportRepo = new Mock<IGenericRepository<PostReport>>();
            var mockMediaService = new Mock<IMediaService>();
            var mockLogger = new Mock<ILogger<PostService>>();

            var service = new PostService(
                mockPostRepo.Object,
                mockUserRepo.Object,
                mockLikeRepo.Object,
                mockReportRepo.Object,
                mockMediaService.Object,
                mockLogger.Object);

            await Assert.ThrowsAsync<BadRequestException>(() =>
                service.GetFeedAsync(1, 10, null, null, null, cursor: "invalid_not_object_id"));
        }

        [Fact]
        public async Task B28_ToggleLike_RestoresSoftDeletedLikeWithoutCallingCreateAsync()
        {
            var postId = "post_like_123";
            var userId = "user_like_123";

            var mockPostRepo = new Mock<IGenericRepository<Post>>();
            var mockUserRepo = new Mock<IGenericRepository<User>>();
            var mockLikeRepo = new Mock<IGenericRepository<PostLike>>();
            var mockReportRepo = new Mock<IGenericRepository<PostReport>>();
            var mockMediaService = new Mock<IMediaService>();
            var mockLogger = new Mock<ILogger<PostService>>();

            var post = new Post { Id = postId, LikeCount = 0 };
            mockPostRepo.Setup(r => r.FindByIdAsync(postId)).ReturnsAsync(post);
            mockPostRepo.Setup(r => r.IncrementFieldAsync(postId, It.IsAny<Expression<Func<Post, int>>>(), It.IsAny<int>()))
                .Callback<string, Expression<Func<Post, int>>, int>((id, field, val) => post.LikeCount += val)
                .ReturnsAsync(true);

            PostLike? savedLike = null;
            var createCallCount = 0;

            mockLikeRepo.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<PostLike, bool>>>()))
                .ReturnsAsync(() => savedLike);

            mockLikeRepo.Setup(r => r.CreateAsync(It.IsAny<PostLike>()))
                .Callback<PostLike>(l =>
                {
                    l.Id = "like_doc_1";
                    savedLike = l;
                    createCallCount++;
                })
                .ReturnsAsync((PostLike l) => l);

            mockLikeRepo.Setup(r => r.UpdateAsync(It.IsAny<string>(), It.IsAny<PostLike>()))
                .Callback<string, PostLike>((id, l) => savedLike = l)
                .Returns(Task.CompletedTask);

            var service = new PostService(
                mockPostRepo.Object,
                mockUserRepo.Object,
                mockLikeRepo.Object,
                mockReportRepo.Object,
                mockMediaService.Object,
                mockLogger.Object);

            // Step 1: First like -> should call CreateAsync
            var result1 = await service.ToggleLikeAsync(postId, userId);
            Assert.True(result1.Liked);
            Assert.Equal(1, createCallCount);
            Assert.False(savedLike!.IsDeleted);

            // Step 2: Unlike -> soft delete (IsDeleted = true)
            var result2 = await service.ToggleLikeAsync(postId, userId);
            Assert.False(result2.Liked);
            Assert.Equal(1, createCallCount); // Still only 1 create call
            Assert.True(savedLike.IsDeleted);

            // Step 3: Like again -> B28 Fix: restores like, does NOT call CreateAsync!
            var result3 = await service.ToggleLikeAsync(postId, userId);
            Assert.True(result3.Liked);
            Assert.Equal(1, createCallCount); // Still 1! Prevented E11000 duplicate key error!
            Assert.False(savedLike.IsDeleted);
            Assert.Null(savedLike.DeletedAt);
        }

        [Fact]
        public async Task B27_ModeratePost_RestoreResetsReportCountToZero()
        {
            var postId = "post_reported_123";
            var mockPostRepo = new Mock<IGenericRepository<Post>>();
            var mockUserRepo = new Mock<IGenericRepository<User>>();
            var mockLikeRepo = new Mock<IGenericRepository<PostLike>>();
            var mockReportRepo = new Mock<IGenericRepository<PostReport>>();
            var mockMediaService = new Mock<IMediaService>();
            var mockLogger = new Mock<ILogger<PostService>>();

            var post = new Post
            {
                Id = postId,
                UserId = "author_1",
                Status = "Pending",
                ReportCount = 3,
                RejectionReason = "Inappropriate"
            };

            mockPostRepo.Setup(r => r.FindByIdAsync(postId)).ReturnsAsync(post);
            mockPostRepo.Setup(r => r.UpdateAsync(postId, It.IsAny<Post>())).Returns(Task.CompletedTask);

            var service = new PostService(
                mockPostRepo.Object,
                mockUserRepo.Object,
                mockLikeRepo.Object,
                mockReportRepo.Object,
                mockMediaService.Object,
                mockLogger.Object);

            var response = await service.ModeratePostAsync(postId, "restore");

            Assert.Equal("Published", post.Status);
            Assert.Equal(0, post.ReportCount); // B27: Report count must be reset to 0
            Assert.Null(post.RejectionReason);
        }

        [Fact]
        public async Task B16_And_B17_CommentDeletionCascadesAndCreatedAtHasNullUpdatedAt()
        {
            var postId = "post_comm_1";
            var parentId = "parent_comm_1";
            var userId = "user_comm_1";

            var mockCommentRepo = new Mock<IGenericRepository<Comment>>();
            var mockPostRepo = new Mock<IGenericRepository<Post>>();
            var mockUserRepo = new Mock<IGenericRepository<User>>();

            var post = new Post { Id = postId, CommentCount = 3 };
            mockPostRepo.Setup(r => r.FindByIdAsync(postId)).ReturnsAsync(post);
            mockPostRepo.Setup(r => r.IncrementFieldAsync(postId, It.IsAny<Expression<Func<Post, int>>>(), It.IsAny<int>()))
                .Callback<string, Expression<Func<Post, int>>, int>((id, field, val) => post.CommentCount += val)
                .ReturnsAsync(true);

            var parentComment = new Comment
            {
                Id = parentId,
                PostId = postId,
                UserId = userId,
                Content = "Top level comment",
                ReplyCount = 2,
                UpdatedAt = null
            };

            var reply1 = new Comment
            {
                Id = "reply_1",
                PostId = postId,
                ParentId = parentId,
                UserId = "user_comm_2",
                Content = "Reply 1"
            };

            var reply2 = new Comment
            {
                Id = "reply_2",
                PostId = postId,
                ParentId = parentId,
                UserId = "user_comm_3",
                Content = "Reply 2"
            };

            var commentDb = new List<Comment> { parentComment, reply1, reply2 };

            mockCommentRepo.Setup(r => r.FindByIdAsync(parentId)).ReturnsAsync(parentComment);
            mockCommentRepo.Setup(r => r.FindAsync(It.IsAny<Expression<Func<Comment, bool>>>()))
                .ReturnsAsync((Expression<Func<Comment, bool>> pred) => commentDb.AsQueryable().Where(pred).ToList());
            mockCommentRepo.Setup(r => r.CreateAsync(It.IsAny<Comment>()))
                .ReturnsAsync((Comment c) =>
                {
                    c.Id = Guid.NewGuid().ToString();
                    commentDb.Add(c);
                    return c;
                });
            mockCommentRepo.Setup(r => r.UpdateAsync(It.IsAny<string>(), It.IsAny<Comment>()))
                .Callback<string, Comment>((id, updated) =>
                {
                    var idx = commentDb.FindIndex(c => c.Id == id);
                    if (idx >= 0) commentDb[idx] = updated;
                })
                .Returns(Task.CompletedTask);

            var service = new CommentService(mockCommentRepo.Object, mockPostRepo.Object, mockUserRepo.Object);

            // B17 Verification: newly created comment has UpdatedAt == null
            var newComment = await service.CreateCommentAsync(postId, new CreateCommentRequest { Content = "Fresh comment" }, userId);
            Assert.Null(newComment.UpdatedAt);

            // B16 Verification: deleting parent comment cascades to all replies and decrements count by 3
            var deleteResult = await service.DeleteCommentAsync(parentId, userId, "User");
            Assert.True(deleteResult);
            Assert.True(parentComment.IsDeleted);
            Assert.True(reply1.IsDeleted);
            Assert.True(reply2.IsDeleted);
            Assert.Equal(1, post.CommentCount); // was 3 (+ 1 created = 4), deleted 3 -> 1
        }
    }
}
