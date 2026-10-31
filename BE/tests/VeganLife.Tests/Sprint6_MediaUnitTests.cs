using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using ApplicationLayer.Services;
using CloudinaryDotNet;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint6_MediaUnitTests
    {
        [Fact]
        public async Task B21_VideoPost_DoesNotReturnFakeAiStatus()
        {
            var mockPostRepo = new Mock<IGenericRepository<Post>>();
            var mockUserRepo = new Mock<IGenericRepository<User>>();
            var mockLikeRepo = new Mock<IGenericRepository<PostLike>>();
            var mockReportRepo = new Mock<IGenericRepository<PostReport>>();
            var mockMediaService = new Mock<IMediaService>();
            var mockLogger = new Mock<ILogger<PostService>>();

            var post = new Post
            {
                Id = "video_post_1",
                UserId = "user_1",
                Title = "Video test",
                Body = "Testing video post",
                MediaType = "Video",
                MediaUrl = "https://res.cloudinary.com/demo/video/upload/sample.mp4",
                Status = "Published"
            };

            mockPostRepo.Setup(r => r.FindByIdAsync("video_post_1")).ReturnsAsync(post);
            mockUserRepo.Setup(r => r.FindByIdAsync("user_1")).ReturnsAsync(new User { Id = "user_1", FullName = "Chef Hoang" });

            var service = new PostService(
                mockPostRepo.Object,
                mockUserRepo.Object,
                mockLikeRepo.Object,
                mockReportRepo.Object,
                mockMediaService.Object,
                mockLogger.Object);

            var result = await service.GetPostByIdAsync("video_post_1", null);

            // B21 Fix: video should be null when no pipeline exists, rather than returning fake aiStatus: ready
            Assert.Null(result.Video);
        }

        [Fact]
        public async Task B32_LocalVideoUpload_SavesDurationAsNullInsteadOfHardcoded15()
        {
            var mockMediaRepo = new Mock<IGenericRepository<MediaAsset>>();
            var mockLogger = new Mock<ILogger<MediaService>>();

            var inMemoryConfig = new Dictionary<string, string?>
            {
                { "Cloudinary:CloudName", "dummy_cloud_name" } // Triggers local upload branch
            };
            var configuration = new ConfigurationBuilder()
                .AddInMemoryCollection(inMemoryConfig)
                .Build();

            MediaAsset? savedAsset = null;
            mockMediaRepo.Setup(r => r.CreateAsync(It.IsAny<MediaAsset>()))
                .Callback<MediaAsset>(a => savedAsset = a)
                .ReturnsAsync((MediaAsset a) => a);

            var dummyCloudinary = new Cloudinary(new Account("dummy_cloud_name", "dummy_key", "dummy_secret"));
            var service = new MediaService(dummyCloudinary, mockMediaRepo.Object, mockLogger.Object);

            // Construct valid MP4 mock file header (ftyp box)
            var mp4Header = new byte[] {
                0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // size 24, "ftyp"
                0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00, // "isom", version
                0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32  // compatible brands
            };

            var stream = new MemoryStream(mp4Header);
            var fileMock = new Mock<IFormFile>();
            fileMock.Setup(f => f.FileName).Returns("test_video.mp4");
            fileMock.Setup(f => f.Length).Returns(mp4Header.Length);
            fileMock.Setup(f => f.OpenReadStream()).Returns(() => new MemoryStream(mp4Header));

            var response = await service.UploadVideoAsync(fileMock.Object, "user_test_b32");

            // B32 Fix: DurationSeconds must be null for local uploads, not hardcoded 15
            Assert.Null(response.DurationSeconds);
            Assert.NotNull(savedAsset);
            Assert.Null(savedAsset!.DurationSeconds);
        }
    }
}
