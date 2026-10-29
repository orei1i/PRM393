using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using DomainLayer.Exceptions;

namespace ControllerLayer.Extensions
{
    public static class ClaimsPrincipalExtensions
    {
        public static string GetUserId(this ClaimsPrincipal principal)
        {
            var userId = GetUserIdOrDefault(principal);
            if (string.IsNullOrWhiteSpace(userId))
            {
                throw new UnauthorizedException("Phiên đăng nhập không hợp lệ hoặc thiếu thông tin định danh.");
            }
            return userId;
        }

        public static string? GetUserIdOrDefault(this ClaimsPrincipal principal)
        {
            if (principal?.Identity?.IsAuthenticated != true)
            {
                return null;
            }

            return principal.FindFirstValue(ClaimTypes.NameIdentifier)
                   ?? principal.FindFirstValue(JwtRegisteredClaimNames.Sub)
                   ?? principal.FindFirst("sub")?.Value;
        }

        public static string? GetRole(this ClaimsPrincipal principal)
        {
            return principal.FindFirstValue(ClaimTypes.Role)
                   ?? principal.FindFirst("role")?.Value;
        }
    }
}
