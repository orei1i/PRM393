using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Logging;
using MongoDB.Bson;

namespace ApplicationLayer.Services
{
    public static class ContentText
    {
        public static string NewId() => ObjectId.GenerateNewId().ToString();

        public static bool IsId(string? value) => ObjectId.TryParse(value, out _);

        /// <summary>Id 24 hex ổn định suy ra từ khoá: cùng dữ liệu luôn cho cùng id, không cần lưu thêm dòng nào.</summary>
        public static string DerivedId(string key)
        {
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(key));
            return Convert.ToHexString(hash, 0, 12).ToLowerInvariant();
        }

        public static BadRequestException Invalid(string message) => new(message, "validation");

        public static List<string> Tokens(string? text) =>
            CommerceText.Fold(text).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).ToList();

        /// <summary>Mọi từ của câu tìm đều khớp đầu một từ (bỏ qua dấu và hoa thường): "hu" khớp "hũ", không khớp "chuối".</summary>
        public static bool Matches(IReadOnlyCollection<string> tokens, params string?[] texts)
        {
            if (tokens.Count == 0) return false;
            var haystack = string.Join(' ', texts.Select(CommerceText.Fold));
            return tokens.All(t => StartsAWord(haystack, t));
        }

        private static bool StartsAWord(string haystack, string token)
        {
            for (var i = haystack.IndexOf(token, StringComparison.Ordinal); i >= 0; i = haystack.IndexOf(token, i + 1, StringComparison.Ordinal))
            {
                if (i == 0 || !char.IsLetterOrDigit(haystack[i - 1])) return true;
            }
            return false;
        }

        /// <summary>Bỏ dấu và viết đầy đủ "Q." "P." như cách người dùng gõ địa chỉ.</summary>
        public static string FoldAddress(string? address)
        {
            var folded = CommerceText.Fold(address);
            folded = Regex.Replace(folded, @"\bq\.\s*", "quan ");
            return Regex.Replace(folded, @"\bp\.\s*", "phuong ");
        }

        public static string FoldedKey(string? a, string? b) =>
            $"{string.Join(' ', Tokens(a))}|{string.Join(' ', Tokens(FoldAddress(b)))}";

        public static double HaversineKm(double lat1, double lng1, double lat2, double lng2)
        {
            const double radiusKm = 6371;
            double Rad(double d) => d * Math.PI / 180;
            var dLat = Rad(lat2 - lat1);
            var dLng = Rad(lng2 - lng1);
            var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
                    + Math.Cos(Rad(lat1)) * Math.Cos(Rad(lat2)) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
            return radiusKm * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        }

        public static void RequireCoordinatePair(double? lat, double? lng)
        {
            if (lat.HasValue != lng.HasValue) throw Invalid("Toạ độ cần đủ vĩ độ và kinh độ.");
            if (lat is < -90 or > 90 || lng is < -180 or > 180) throw Invalid("Toạ độ không hợp lệ.");
        }

        /// <summary>Tỉ lệ thay đổi so với kỳ trước; kỳ trước bằng 0 thì không có tỉ lệ để so, trả 0.</summary>
        public static double Delta(double current, double previous) =>
            previous > 0 ? Math.Round((current - previous) / previous, 4) : 0;

        public static AuthorSummaryDto Author(string userId, User? user) =>
            user is { IsDeleted: false }
                ? new AuthorSummaryDto
                {
                    Id = userId,
                    FullName = user.FullName ?? "Thành viên",
                    IsVerifiedChef = user.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                }
                : new AuthorSummaryDto { Id = userId, FullName = "Thành viên" };

        public static PostResponse MapPost(Post p, User? author) => new()
        {
            Id = p.Id,
            Type = p.Type,
            Author = Author(p.UserId, author),
            Title = p.Title,
            Body = p.Body,
            Tags = p.Tags,
            CoverSeed = p.CoverSeed ?? p.Id,
            LikeCount = Math.Max(0, p.LikeCount),
            CommentCount = Math.Max(0, p.CommentCount),
            Status = p.Status,
            MediaType = p.MediaType,
            MediaUrl = p.MediaUrl,
            IsPinned = p.IsPinned,
            CreatedAt = p.CreatedAt,
            UpdatedAt = p.UpdatedAt
        };
    }

    public class AdminAuditService : IAdminAuditService
    {
        private readonly IGenericRepository<AdminAuditLog> _audit;
        private readonly IGenericRepository<User> _users;
        private readonly IClock _clock;
        private readonly ILogger<AdminAuditService> _logger;

        public AdminAuditService(IGenericRepository<AdminAuditLog> audit, IGenericRepository<User> users, IClock clock, ILogger<AdminAuditService> logger)
        {
            _audit = audit;
            _users = users;
            _clock = clock;
            _logger = logger;
        }

        public async Task<string> NameOfAsync(string adminId)
        {
            var admin = await _users.FindByIdAsync(adminId);
            return string.IsNullOrWhiteSpace(admin?.FullName) ? "Quản trị viên" : admin.FullName;
        }

        public async Task LogAsync(string actor, string action, string target, string? note = null)
        {
            try
            {
                await _audit.CreateAsync(new AdminAuditLog
                {
                    Id = ContentText.NewId(),
                    Actor = actor,
                    Action = action,
                    Target = target,
                    Note = note,
                    CreatedAt = _clock.UtcNow
                });
            }
            catch (Exception ex)
            {
                _logger.LogWarning("Không ghi được nhật ký admin ({ErrorType}).", ex.GetType().Name);
            }
        }
    }
}
