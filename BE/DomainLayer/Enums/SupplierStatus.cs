namespace DomainLayer.Enums;

/// <summary>
/// Current status of a supplier.
/// Stored as int in database.
/// </summary>
public enum SupplierStatus
{
    Inactive = 0,
    Active = 1,
    Suspended = 2
}
