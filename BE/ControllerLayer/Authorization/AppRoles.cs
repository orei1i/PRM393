namespace ControllerLayer.Authorization
{
    /// <summary>
    /// Tên role trong JWT (dùng cho phân quyền API).
    /// </summary>
    public static class AppRoles
    {
        public const string Admin = "Admin";

        public const string Chef = "Chef";

        public const string User = "User";

        public const string Member = "Member";

        public const string AdminOrChef = "Admin,Chef";

        public const string AdminOrMember = "Admin,Member";
    }
}
