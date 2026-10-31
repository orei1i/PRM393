# 🧪 TÀI LIỆU TEST CASES: MEDIA SERVICE & MODULE POST / COMMENT

> **Hệ thống**: VeganLife Backend (.NET 9 Clean Architecture)  
> **Các module**: Media Service (Cloudinary), Posts & Feed (Cộng đồng), Comments & Replies (Bình luận phân cấp)  
> **Base URL**: `http://localhost:5001/api/v1` (hoặc `http://localhost:7211/api/v1`)  
> **Swagger UI**: `http://localhost:5001/swagger`

---

## 📌 MỤC LỤC
1. [Chuẩn bị môi trường & Tài khoản test](#1-chuẩn-bị-môi-trường--tài-khoản-test)
2. [Phần 1: Kiểm thử Media Service](#phần-1-kiểm-thử-media-service)
3. [Phần 2: Kiểm thử Module Posts & Feed](#phần-2-kiểm-thử-module-posts--feed)
4. [Phần 3: Kiểm thử Module Comments & Replies](#phần-3-kiểm-thử-module-comments--replies)
5. [Bảng Checklist Nghiệm Thu](#5-bảng-checklist-nghiệm-thu)

---

## 1. Chuẩn Bị Môi Trường & Tài Khoản Test

### 1.1. Khởi động Backend
Mở Terminal tại thư mục `BE/ControllerLayer`:
```powershell
cd e:\Semester_7\PRM392\Project\PRM393\BE\ControllerLayer
dotnet run
```
Truy cập Swagger tại trình duyệt: 👉 `http://localhost:5001/swagger`

### 1.2. Đăng nhập lấy Bearer Token
* **Endpoint**: `POST /api/v1/auth/login`
* **Request Body**:
```json
{
  "email": "minhanh.nguyen@gmail.com",
  "password": "Password123!"
}
```
* **Response**:
```json
{
  "success": true,
  "message": "Đăng nhập thành công.",
  "data": {
    "accessToken": "eyJhbGciOiJIUzI1Ni...",
    "expiresAt": "2026-10-29T01:15:00Z",
    "user": {
      "id": "672000000000000000000001",
      "email": "minhanh.nguyen@gmail.com",
      "fullName": "Minh Anh",
      "role": "User"
    }
  },
  "statusCode": 200
}
```
* **Cấu hình trên Swagger**:
  Nhấn nút **Authorize 🔒** góc trên bên phải → Dán chuỗi `accessToken` vào ô Value (Swagger đã cấu hình tự động thêm `Bearer `, không cần gõ tay).

---

## Phần 1: Kiểm Thử Media Service

### Test Case M1: Tải ảnh lên thành công (Happy Path)
* **Mục tiêu**: Xác nhận upload ảnh định dạng hợp lệ lên Cloudinary và lưu vào MongoDB.
* **Method & Endpoint**: `POST /api/v1/media/images`
* **Headers**: `Authorization: Bearer {{token}}`
* **Form-Data**:
  * Key: `file` (dạng File)
  * Tệp chọn: 1 file ảnh `.jpg`, `.png`, hoặc `.webp` (< 10 MB)
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response body:
```json
{
  "success": true,
  "message": "Tải ảnh lên thành công.",
  "data": {
    "mediaUrl": "https://res.cloudinary.com/.../veganlife/images/abcxyz.jpg",
    "sizeBytes": 204850,
    "width": 1200,
    "height": 800
  },
  "statusCode": 200
}
```

---

### Test Case M2: Upload ảnh vượt quá dung lượng tối đa 10 MB
* **Mục tiêu**: Kiểm tra giới hạn 10 MB của ảnh.
* **Method & Endpoint**: `POST /api/v1/media/images`
* **Form-Data**: Chọn file ảnh có dung lượng > 10 MB (ví dụ 12 MB)
* **Kết quả mong đợi**:
  * Status code: `413 Payload Too Large`
  * Response body:
```json
{
  "success": false,
  "message": "Ảnh vượt quá dung lượng tối đa 10 MB.",
  "statusCode": 413
}
```

---

### Test Case M3: Upload sai định dạng ảnh
* **Mục tiêu**: Chặn các định dạng tài liệu không thuộc danh sách ảnh được hỗ trợ.
* **Method & Endpoint**: `POST /api/v1/media/images`
* **Form-Data**: Chọn file `.pdf`, `.zip`, `.exe`, `.docx`
* **Kết quả mong đợi**:
  * Status code: `415 Unsupported Media Type`
  * Response body:
```json
{
  "success": false,
  "message": "Định dạng ảnh không được hỗ trợ. Chỉ chấp nhận JPG, PNG, WEBP, HEIC.",
  "statusCode": 415
}
```

---

### Test Case M4: Chống giả mạo phần mở rộng file (Magic Bytes Check)
* **Mục tiêu**: Ngăn chặn kẻ gian đổi đuôi file `.txt` hoặc `.exe` thành `.jpg` để bypass kiểm tra đuôi file.
* **Method & Endpoint**: `POST /api/v1/media/images`
* **Thực hiện**: Tạo 1 file text nội dung `"hello world"` rồi đổi tên thành `fake_image.jpg`, sau đó upload.
* **Kết quả mong đợi**:
  * Status code: `415 Unsupported Media Type`
  * Response body:
```json
{
  "success": false,
  "message": "Tệp hình ảnh không hợp lệ hoặc đã bị đổi phần mở rộng.",
  "statusCode": 415
}
```

---

### Test Case M5: Tải video lên thành công (Happy Path)
* **Mục tiêu**: Upload video dung lượng hợp lệ bằng cơ chế chunked upload của Cloudinary.
* **Method & Endpoint**: `POST /api/v1/media/videos`
* **Headers**: `Authorization: Bearer {{token}}`
* **Form-Data**:
  * Key: `file`
  * Tệp chọn: 1 file video ngắn `.mp4`, `.mov`, hoặc `.webm` (< 100 MB)
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response body:
```json
{
  "success": true,
  "message": "Tải video lên thành công.",
  "data": {
    "mediaUrl": "https://res.cloudinary.com/.../veganlife/videos/xyz123.mp4",
    "durationSeconds": 15,
    "sizeBytes": 5242880
  },
  "statusCode": 200
}
```

---

### Test Case M6: Upload video vượt quá giới hạn 100 MB
* **Mục tiêu**: Kiểm tra giới hạn tối đa 100 MB cho gói Free.
* **Method & Endpoint**: `POST /api/v1/media/videos`
* **Form-Data**: Chọn file video dung lượng > 100 MB (ví dụ 105 MB)
* **Kết quả mong đợi**:
  * Status code: `413 Payload Too Large`
  * Response body:
```json
{
  "success": false,
  "message": "Video vượt quá dung lượng tối đa 100 MB.",
  "statusCode": 413
}
```

---

### Test Case M7: Upload khi chưa đăng nhập
* **Mục tiêu**: Đảm bảo endpoint upload được bảo vệ bằng JWT.
* **Method & Endpoint**: `POST /api/v1/media/images`
* **Headers**: Không gửi header `Authorization`
* **Kết quả mong đợi**:
  * Status code: `401 Unauthorized`

---

## Phần 2: Kiểm Thử Module Posts & Feed

### Test Case P1: Xem bảng tin Feed ở chế độ khách (Guest)
* **Mục tiêu**: Khách chưa đăng nhập vẫn đọc được bảng tin công khai.
* **Method & Endpoint**: `GET /api/v1/posts?page=1&pageSize=10`
* **Headers**: Không cần Token
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response body:
```json
{
  "success": true,
  "message": null,
  "data": {
    "items": [
      {
        "id": "672000000000000000000010",
        "type": "discussion",
        "author": {
          "id": "672000000000000000000001",
          "fullName": "Minh Anh",
          "isVerifiedChef": false
        },
        "title": "Hỏi kinh nghiệm nấu phở chay",
        "body": "Nước dùng phở chay hầm rau củ thế nào để ngọt thanh tự nhiên ạ?",
        "tags": ["pho-chay", "nau-an"],
        "likeCount": 5,
        "commentCount": 2,
        "likedByMe": false,
        "status": "Published",
        "mediaType": "Text",
        "mediaUrl": null,
        "createdAt": "2026-10-29T00:10:00Z"
      }
    ],
    "page": 1,
    "pageSize": 10,
    "totalItems": 1,
    "totalPages": 1
  },
  "statusCode": 200
}
```

---

### Test Case P2: Đăng bài viết mới dạng Thảo luận (Text)
* **Mục tiêu**: Người dùng tạo bài viết chỉ có chữ.
* **Method & Endpoint**: `POST /api/v1/posts`
* **Headers**: `Authorization: Bearer {{token}}`
* **Request Body**:
```json
{
  "type": "discussion",
  "title": "Chia sẻ quán bún bò chay ngon ở Quận 1",
  "body": "Hôm nay mình vừa khám phá ra một quán chay nằm trong hẻm Nguyễn Trãi, nước dùng đậm đà sa tế cực đỉnh!",
  "tags": ["quan-ngon", "quan-1"],
  "mediaType": "Text"
}
```
* **Kết quả mong đợi**:
  * Status code: `201 Created`
  * Response body trả về thông tin bài viết với `likeCount: 0`, `commentCount: 0`, `status: "Published"`.

---

### Test Case P3: Đăng bài viết công thức kèm ảnh hợp lệ
* **Mục tiêu**: Tạo bài viết có đính kèm ảnh vừa upload từ Cloudinary (hợp lệ quyền sở hữu).
* **Method & Endpoint**: `POST /api/v1/posts`
* **Headers**: `Authorization: Bearer {{token}}`
* **Request Body**: (Lấy `mediaUrl` từ kết quả Test Case M1)
```json
{
  "type": "recipe",
  "title": "Công thức nấm đùi gà kho tiêu xanh đậm vị",
  "body": "Nấm đùi gà cắt miếng vừa ăn, ướp cùng nước tương, tiêu xanh đập dập và kho lửa nhỏ trong 15 phút.",
  "tags": ["mon-kho", "de-nau"],
  "mediaType": "Image",
  "mediaUrl": "https://res.cloudinary.com/.../veganlife/images/abcxyz.jpg"
}
```
* **Kết quả mong đợi**:
  * Status code: `201 Created`
  * Bài viết được lưu với `mediaUrl` và hiển thị trên feed.

---

### Test Case P4: Đăng bài viết với Media giả mạo (Không do user upload)
* **Mục tiêu**: Chặn việc chèn URL ảnh rác từ nguồn bên ngoài mà không thông qua Media Service của hệ thống.
* **Method & Endpoint**: `POST /api/v1/posts`
* **Headers**: `Authorization: Bearer {{token}}`
* **Request Body**:
```json
{
  "type": "recipe",
  "title": "Hack link ảnh ngoài",
  "body": "Nội dung giả mạo",
  "mediaUrl": "https://google.com/random-external-image.jpg"
}
```
* **Kết quả mong đợi**:
  * Status code: `400 Bad Request`
  * Response: `"Tài nguyên media không tồn tại hoặc không thuộc quyền sở hữu của bạn."`

---

### Test Case P5: Xem chi tiết bài viết theo ID
* **Mục tiêu**: Lấy đầy đủ thông tin bài viết và tác giả.
* **Method & Endpoint**: `GET /api/v1/posts/{id}`
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Trả về chi tiết bài viết tương ứng.

---

### Test Case P6: Thích bài viết lần 1 (Toggle Like - ON)
* **Mục tiêu**: Like bài viết, số like tăng 1.
* **Method & Endpoint**: `POST /api/v1/posts/{id}/like`
* **Headers**: `Authorization: Bearer {{token}}`
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response body:
```json
{
  "success": true,
  "message": "Đã thích bài viết.",
  "data": {
    "liked": true,
    "likeCount": 1
  },
  "statusCode": 200
}
```

---

### Test Case P7: Bỏ thích bài viết lần 2 (Toggle Like - OFF)
* **Mục tiêu**: Nhấn like lần nữa trên cùng bài viết → chuyển sang trạng thái bỏ like, số like giảm 1.
* **Method & Endpoint**: `POST /api/v1/posts/{id}/like` (gọi lại đúng endpoint trên)
* **Headers**: `Authorization: Bearer {{token}}`
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response body:
```json
{
  "success": true,
  "message": "Đã bỏ thích bài viết.",
  "data": {
    "liked": false,
    "likeCount": 0
  },
  "statusCode": 200
}
```

---

### Test Case P8: Báo cáo bài viết vi phạm
* **Mục tiêu**: Người dùng báo cáo bài viết vi phạm tiêu chuẩn cộng đồng.
* **Method & Endpoint**: `POST /api/v1/posts/{id}/reports`
* **Headers**: `Authorization: Bearer {{token}}`
* **Request Body**:
```json
{
  "reason": "Bài viết có chứa hình ảnh không thuần chay."
}
```
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response: `"Báo cáo bài viết thành công. Cảm ơn bạn đã hỗ trợ cộng đồng."`

---

### Test Case P9: Báo cáo trùng lặp bài viết
* **Mục tiêu**: Một user không thể báo cáo nhiều lần trên cùng một bài viết.
* **Method & Endpoint**: `POST /api/v1/posts/{id}/reports` (gọi lại đúng endpoint trên với cùng token)
* **Kết quả mong đợi**:
  * Status code: `409 Conflict`
  * Response: `"Bạn đã báo cáo bài viết này rồi."`

---

### Test Case P10: Tự động ẩn bài viết khi nhận đủ 3 lượt báo cáo
* **Mục tiêu**: Cơ chế kiểm duyệt tự động: khi có 3 tài khoản khác nhau báo cáo 1 bài, bài viết tự động chuyển `status: "Pending"` và ẩn khỏi bảng tin feed.
* **Thực hiện**:
  1. Tạo bài viết mới.
  2. Dùng 3 tài khoản khác nhau (hoặc 3 token khác nhau) lần lượt gọi `POST /api/v1/posts/{id}/reports`.
  3. Gọi lại `GET /api/v1/posts` (Feed).
* **Kết quả mong đợi**: Bài viết đó **biến mất hoàn toàn** khỏi kết quả Feed của Guest và Member.

---

### Test Case P11: Xóa bài viết của người khác (Bị từ chối)
* **Mục tiêu**: Bảo mật quyền tác giả.
* **Method & Endpoint**: `DELETE /api/v1/posts/{id}`
* **Thực hiện**: Đăng nhập tài khoản B, cố gắng xóa bài viết do tài khoản A đăng.
* **Kết quả mong đợi**:
  * Status code: `403 Forbidden`
  * Response: `"Bạn không có quyền xóa bài viết này."`

---

### Test Case P12: Xóa bài viết của chính mình (Thành công)
* **Mục tiêu**: Xóa mềm bài viết.
* **Method & Endpoint**: `DELETE /api/v1/posts/{id}`
* **Thực hiện**: Đăng nhập đúng tài khoản tạo bài viết, thực hiện xóa.
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response: `"Xóa bài viết thành công."`
  * Gọi lại `GET /api/v1/posts/{id}` trả về `404 Not Found`.

---

## Phần 3: Kiểm Thử Module Comments & Replies

### Test Case C1: Thêm bình luận gốc (Top-level comment)
* **Mục tiêu**: Bình luận vào một bài viết.
* **Method & Endpoint**: `POST /api/v1/posts/{id}/comments`
* **Headers**: `Authorization: Bearer {{token}}`
* **Request Body**:
```json
{
  "content": "Bài viết chia sẻ rất hữu ích, cảm ơn bạn nhiều nhé!"
}
```
* **Kết quả mong đợi**:
  * Status code: `201 Created`
  * Response body:
```json
{
  "success": true,
  "message": "Gửi bình luận thành công.",
  "data": {
    "id": "672000000000000000000050",
    "postId": "672000000000000000000010",
    "parentId": null,
    "author": {
      "id": "672000000000000000000001",
      "fullName": "Minh Anh",
      "isVerifiedChef": false
    },
    "content": "Bài viết chia sẻ rất hữu ích, cảm ơn bạn nhiều nhé!",
    "replyCount": 0,
    "replies": []
  },
  "statusCode": 201
}
```
  * `commentCount` của bài viết tăng lên 1.

---

### Test Case C2: Thêm phản hồi con cho bình luận gốc (Reply / Sub-comment)
* **Mục tiêu**: Trả lời một bình luận (phản hồi 1 cấp).
* **Method & Endpoint**: `POST /api/v1/posts/{id}/comments`
* **Headers**: `Authorization: Bearer {{token}}`
* **Request Body**: (Lấy `id` từ Test Case C1 điền vào `parentId`)
```json
{
  "content": "Không có gì bạn ơi, cùng lan tỏa lối sống thuần chay nhé!",
  "parentId": "672000000000000000000050"
}
```
* **Kết quả mong đợi**:
  * Status code: `201 Created`
  * Bình luận gốc được tăng `replyCount` lên 1.

---

### Test Case C3: Lấy danh sách bình luận của bài viết
* **Mục tiêu**: Đọc bình luận phân trang, mới nhất trước, hiển thị kèm preview 2 phản hồi đầu tiên theo hợp đồng Flutter.
* **Method & Endpoint**: `GET /api/v1/posts/{id}/comments?page=1&pageSize=10`
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response trả về danh sách các bình luận gốc; mỗi bình luận gốc có mảng `replies` chứa các phản hồi con.

---

### Test Case C4: Xóa bình luận của người khác (Bị từ chối)
* **Mục tiêu**: Bảo vệ bình luận cá nhân.
* **Method & Endpoint**: `DELETE /api/v1/comments/{commentId}`
* **Thực hiện**: Dùng token của User B để xóa comment của User A.
* **Kết quả mong đợi**:
  * Status code: `403 Forbidden`
  * Response: `"Bạn không có quyền xóa bình luận này."`

---

### Test Case C5: Xóa bình luận chính chủ (Thành công)
* **Mục tiêu**: Xóa mềm bình luận của chính mình.
* **Method & Endpoint**: `DELETE /api/v1/comments/{commentId}`
* **Thực hiện**: Dùng đúng token của người tạo bình luận để xóa.
* **Kết quả mong đợi**:
  * Status code: `200 OK`
  * Response: `"Xóa bình luận thành công."`
  * Số lượng `commentCount` của bài viết tương ứng tự động giảm 1.

---

## 5. Bảng Checklist Nghiệm Thu

| Nhóm | Mã Test Case | Tên Chức Năng | Trạng Thái |
|:---:|:---:|---|:---:|
| **Media** | M1 | Upload ảnh hợp lệ (< 10 MB) | [ ] |
| | M2 | Chặn ảnh quá dung lượng (> 10 MB) | [ ] |
| | M3 | Chặn tệp sai định dạng ảnh | [ ] |
| | M4 | Chặn tệp giả mạo extension (Magic Bytes) | [ ] |
| | M5 | Upload video hợp lệ (< 100 MB) | [ ] |
| | M6 | Chặn video quá dung lượng (> 100 MB) | [ ] |
| | M7 | Chặn upload khi thiếu Token (401) | [ ] |
| **Posts** | P1 | Guest đọc bảng tin Feed phân trang | [ ] |
| | P2 | Member đọc Feed kèm cờ `likedByMe` | [ ] |
| | P3 | Đăng bài viết thảo luận (Text) | [ ] |
| | P4 | Chặn chèn link ảnh ngoài giả mạo | [ ] |
| | P5 | Xem chi tiết bài viết kèm tác giả | [ ] |
| | P6 | Thích bài viết lần 1 (Like Count tăng 1) | [ ] |
| | P7 | Bỏ thích bài viết lần 2 (Like Count giảm 1) | [ ] |
| | P8 | Gửi báo cáo bài viết vi phạm | [ ] |
| | P9 | Chặn báo cáo trùng lặp từ một người | [ ] |
| | P10 | Bài viết bị report 3 lần tự ẩn khỏi Feed | [ ] |
| | P11 | Chặn xóa bài của người khác (403) | [ ] |
| | P12 | Chủ bài viết xóa bài thành công | [ ] |
| **Comments** | C1 | Gửi bình luận gốc (Comment Count tăng 1) | [ ] |
| | C2 | Gửi phản hồi con (Reply Count tăng 1) | [ ] |
| | C3 | Xem bình luận kèm 2 replies preview | [ ] |
| | C4 | Chặn xóa bình luận người khác (403) | [ ] |
| | C5 | Xóa bình luận chính chủ (Comment Count giảm) | [ ] |
