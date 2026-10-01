using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

public static class RoleHierarchy
{
    public const int Admin = 4;
    public const int Manager = 3;
    public const int Staff = 2;
    public const int Customer = 1;

    public static int GetLevel(string roleName)
    {
        return roleName switch
        {
            "Admin" => Admin,
            "Manager" => Manager,
            "Staff" => Staff,
            "Customer" => Customer,
            _ => 0 // Invalid
        };
    }
}