using System;

namespace DomainLayer.Constants
{
    public class GeneralConst
    {
        // ====================
        // ROLE GUIDs
        // ====================
        public const string ADMIN_ROLE_GUID = "11111111-1111-1111-1111-111111111111";
        public const string MANAGER_ROLE_GUID = "22222222-2222-2222-2222-222222222222";
        public const string STAFFPOS_ROLE_GUID = "44444444-4444-4444-4444-444444444444";
        public const string STAFFDELI_ROLE_GUID = "55555555-5555-5555-5555-555555555555";
        public const string CUSTOMER_ROLE_GUID = "33333333-3333-3333-3333-333333333333";

        // ====================
        // AUTHENTICATION MODULE PERMISSION GUIDs
        // ====================
        public const string MANAGE_OWN_PROFILE_PERM_GUID = "a0000000-0000-0000-0000-000000000001";
        public const string CHANGE_OWN_PASSWORD_PERM_GUID = "a0000000-0000-0000-0000-000000000002";
        public const string RESET_PASSWORD_PERM_GUID = "a0000000-0000-0000-0000-000000000003";

        // ====================
        // USER MANAGEMENT MODULE PERMISSION GUIDs
        // ====================
        public const string CREATE_USER_PERM_GUID = "b0000000-0000-0000-0000-000000000001";
        public const string READ_USERS_PERM_GUID = "b0000000-0000-0000-0000-000000000002";
        public const string UPDATE_USER_PERM_GUID = "b0000000-0000-0000-0000-000000000003";
        public const string DELETE_USER_PERM_GUID = "b0000000-0000-0000-0000-000000000004";
        public const string LOCK_USER_PERM_GUID = "b0000000-0000-0000-0000-000000000005";

        // ====================
        // ROLE MANAGEMENT MODULE PERMISSION GUIDs
        // ====================
        public const string CREATE_ROLE_PERM_GUID = "c0000000-0000-0000-0000-000000000001";
        public const string READ_ROLES_PERM_GUID = "c0000000-0000-0000-0000-000000000002";
        public const string UPDATE_ROLE_PERM_GUID = "c0000000-0000-0000-0000-000000000003";
        public const string DELETE_ROLE_PERM_GUID = "c0000000-0000-0000-0000-000000000004";

        // ====================
        // PERMISSION MANAGEMENT MODULE PERMISSION GUIDs
        // ====================
        public const string CREATE_PERMISSION_PERM_GUID = "d0000000-0000-0000-0000-000000000001";
        public const string READ_PERMISSIONS_PERM_GUID = "d0000000-0000-0000-0000-000000000002";
        public const string UPDATE_PERMISSION_PERM_GUID = "d0000000-0000-0000-0000-000000000003";
        public const string DELETE_PERMISSION_PERM_GUID = "d0000000-0000-0000-0000-000000000004";
        public const string ASSIGN_PERMISSION_TO_ROLE_PERM_GUID = "d0000000-0000-0000-0000-000000000005";

        // ====================
        // ORDER MODULE PERMISSION GUIDs
        // ====================
        public const string CREATE_ORDER_ONLINE_PERM_GUID = "e0000000-0000-0000-0000-000000000001";
        public const string VIEW_OWN_ORDERS_PERM_GUID = "e0000000-0000-0000-0000-000000000002";
        public const string CANCEL_OWN_ORDER_PERM_GUID = "e0000000-0000-0000-0000-000000000003";
        public const string TRACK_OWN_ORDER_PERM_GUID = "e0000000-0000-0000-0000-000000000004";
        
        public const string CREATE_POS_ORDER_PERM_GUID = "e0000000-0000-0000-0000-000000000011";
        public const string VIEW_ALL_ORDERS_PERM_GUID = "e0000000-0000-0000-0000-000000000012";
        public const string UPDATE_ORDER_STATUS_PERM_GUID = "e0000000-0000-0000-0000-000000000013";
        public const string EDIT_ORDER_PERM_GUID = "e0000000-0000-0000-0000-000000000014";
        public const string ESTIMATE_PREPARATION_TIME_PERM_GUID = "e0000000-0000-0000-0000-000000000015";
        
        public const string REASSIGN_ORDER_PERM_GUID = "e0000000-0000-0000-0000-000000000021";
        public const string FLAG_PROBLEMATIC_ORDER_PERM_GUID = "e0000000-0000-0000-0000-000000000022";
        public const string VIEW_ORDER_HISTORY_PERM_GUID = "e0000000-0000-0000-0000-000000000023";

        // ====================
        // PAYMENT MODULE PERMISSION GUIDs
        // ====================
        public const string ATTACH_PAYMENT_PERM_GUID = "f0000000-0000-0000-0000-000000000001";
        public const string VIEW_OWN_PAYMENT_PERM_GUID = "f0000000-0000-0000-0000-000000000002";
        public const string VIEW_ALL_PAYMENTS_PERM_GUID = "f0000000-0000-0000-0000-000000000011";
        public const string PROCESS_REFUND_PERM_GUID = "f0000000-0000-0000-0000-000000000012";
        public const string CONFIGURE_PAYMENT_METHOD_PERM_GUID = "f0000000-0000-0000-0000-000000000013";

        // ====================
        // SHIFT / STAFF ASSIGNMENT
        // ====================
        /// <summary>Số nhân viên tối đa trên một ca (đăng ký, duyệt, phân ca thủ công).</summary>
        public const int MaxStaffPerShift = 2;
    }
}