namespace DomainLayer.Constants
{
    public static class UserCacheKeys
    {
        public static string UserStatus(string userId) => $"user_status_{userId}";
    }
}

