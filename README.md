# VeganLife

VeganLife là nền tảng cho người ăn thuần chay: lên thực đơn, quét tủ lạnh, tìm công thức, hỏi trợ lý dinh dưỡng, đặt chuyên gia và tìm quán chay. Đây là đồ án môn PRM393, đang ở mức **bản demo chạy local**, chưa triển khai công khai và không dùng tiền thật.

| Phần | Thư mục | Công nghệ | Dành cho |
|---|---|---|---|
| Ứng dụng di động | [`FE/Mobile`](FE/Mobile/README.md) | Flutter, Riverpod, Dio | Khách, thành viên, chuyên gia |
| Trang quản trị | [`FE/Web`](FE/Web/README.md) | Next.js 15, TypeScript, Tailwind CSS | Ban quản trị |
| Backend | [`BE`](BE/README.md) | .NET 9, Clean Architecture, MongoDB | API `/api/v1` cho cả hai |

## Tính năng

**Ứng dụng di động**

- **Thực đơn:** tạo thực đơn tuần theo hồ sơ sức khoẻ, dị ứng và số bữa trong ngày.
- **Công thức:** chỉnh số người nấu, định lượng tính theo khẩu phần. Đổi nguyên liệu bằng gợi ý có sẵn, món trong tủ lạnh hoặc tự nhập, và app từ chối nguyên liệu không thuần chay.
- **Quét tủ lạnh:** nhận diện thực phẩm từ ảnh bằng Gemini, phân biệt món thuần chay với món có nguồn gốc động vật, rồi lưu vào tủ lạnh.
- **Trợ lý dinh dưỡng:** trả lời từ kho tài liệu đã duyệt (RAG), kèm nguồn trích dẫn, và từ chối câu hỏi ngoài phạm vi.
- **Cộng đồng:** bài viết, video ngắn, bình luận, lưu bài. Bài của người dùng phải được admin duyệt mới lên bảng tin.
- **Chuyên gia:** đặt lịch, nhận báo giá, thanh toán giữ tiền, ví và rút tiền.
- **Quán chay:** danh sách quán, đánh giá, gợi ý quán mới và gắn quán vào bài viết.

**Trang quản trị**

Duyệt bài viết, quán và tài liệu RAG; xử lý khiếu nại và rút tiền; quản lý người dùng, chuyên gia, đơn hàng, quảng cáo và cấu hình mô hình AI.

## Chạy thử

Cần có .NET 9 SDK, MongoDB chạy ở `localhost:27017`, Flutter 3.38 trở lên, Node.js và Android Studio.

**1. Backend** chạy ở `http://localhost:5001`. Đặt biến môi trường trong terminal rồi chạy:

```bash
cd BE/ControllerLayer
ASPNETCORE_ENVIRONMENT=Development dotnet run --no-launch-profile --urls http://localhost:5001
```

Lệnh trên dùng cú pháp Bash. Với PowerShell, đặt biến bằng `$env:TEN_BIEN = 'gia_tri'` trước khi chạy.

| Biến môi trường | Dùng để |
|---|---|
| `DatabaseName` | Chọn DB của ứng dụng. DB trống sẽ được tạo sẵn tài khoản và dữ liệu mẫu |
| `RagDatabaseName` | Chọn DB riêng cho RAG. Thiếu biến này thì chatbot trả 503 |
| `Gemini__ApiKey` | Key Gemini cho chatbot và quét ảnh. Đừng ghi key vào file hay commit |

Tài khoản mẫu nằm ở mục 10.1 của [`BE/TAI_LIEU_API_CHO_FRONTEND.md`](BE/TAI_LIEU_API_CHO_FRONTEND.md).

**2. Ứng dụng di động** trên máy ảo Android (`10.0.2.2` là địa chỉ của máy tính khi nhìn từ máy ảo):

```bash
cd FE/Mobile
flutter pub get
flutter run --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=http://10.0.2.2:5001/api/v1
```

Không truyền `USE_MOCK_DATA=false` thì app chạy bằng dữ liệu mô phỏng, không cần BE.

**3. Trang quản trị**, tạo `FE/Web/.env.local` từ `.env.example` rồi đặt:

```
NEXT_PUBLIC_USE_MOCK_DATA=false
NEXT_PUBLIC_API_BASE_URL=http://localhost:5001/api/v1
```

```bash
cd FE/Web
npm install
npm run dev
```

Mở `http://localhost:3000`. Tài khoản admin chỉ đăng nhập được trên trang quản trị, không đăng nhập được trên app.

## Kiểm thử

```bash
dotnet test BE/VeganLife.Backend.sln
```

```bash
cd FE/Mobile && flutter analyze && flutter test
```

```bash
cd FE/Web && npm run lint && npm run build
```

Bộ `FE/Mobile/integration_test_be` chạy với BE thật. Các test trong đó đăng bài rồi đọc lại ngay, nên BE cho bộ này cần đặt `Posts__RequireApproval=false`. Cách chạy nằm ở mục "Chạy với BE thật" trong [README của Mobile](FE/Mobile/README.md).

## Giới hạn hiện tại

| Phần | Tình trạng |
|---|---|
| Thanh toán | Chỉ có cổng thử nghiệm Sandbox, không có tiền thật |
| Thực đơn | Do thuật toán trong BE tạo, không gọi mô hình AI |
| Trích công thức từ video | Công thức mẫu có ghi nhãn |
| Tìm địa chỉ, GPS | Mô phỏng và có ghi rõ trên app |
| Email | Chưa có dịch vụ gửi. Mã đặt lại mật khẩu chỉ có ở chế độ dev |
| AI kiểm duyệt bài | Chưa có, bài do admin duyệt bằng tay |

**Cần làm trước khi công khai:** bắt đăng nhập cho `POST /vision/scan` (hiện khách gọi được và tiêu hạn mức Gemini), giới hạn CORS đang mở mọi nguồn, xử lý việc thời gian phản hồi đăng nhập để lộ email có tồn tại, thay các khoá và mật khẩu dev trong `appsettings`, và chỉ bật `Payment:Provider=Sandbox`, `Seed:DemoContent` ở môi trường dev.

## Tài liệu

- [Tài liệu API cho frontend](BE/TAI_LIEU_API_CHO_FRONTEND.md)
- [Quy ước code backend](BE/AGENTS.md)
- README chi tiết của [Mobile](FE/Mobile/README.md), [Web](FE/Web/README.md) và [Backend](BE/README.md)
