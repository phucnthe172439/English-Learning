# Sổ theo dõi Xoá mù chữ Cloud

Team SBU3 · 19/10 – 1/12/2026

> Chuyển từ trang tracker (`Sổ theo dõi Xoá mù chữ.html`). Chỉ gồm phần lịch học; điểm danh, chấm điểm và vòng quay host nằm trên trang gốc.

**Cách chấm mỗi ngày:** dựa trên mục *Tự đánh giá: đạt khi* (tiêu chí bắt buộc).

| Mức | Nghĩa |
|---|---|
| **X** Xanh | Đạt mọi tiêu chí bắt buộc |
| **V** Vàng | Thiếu 1–2 tiêu chí |
| **Đ** Đỏ | Thiếu từ 3 tiêu chí |
| · | Chưa chấm |

Số nhỏ cạnh mức là điểm chất lượng 1–5.

## Mục lục

| Tuần | Chủ đề | Thời gian | Mốc tuần |
|---|---|---|---|
| 1 | [Docker](#tuần-1-docker) | 19–25/10 | Người khác clone repo, chạy `docker compose up` là dùng được TeamBoard. |
| 2 | [AWS cơ bản](#tuần-2-aws-cơ-bản) | 26/10–1/11 | TeamBoard chạy trên AWS với URL public, dữ liệu lưu trên RDS. |
| 3 | [AWS vận hành](#tuần-3-aws-vận-hành) | 2–8/11 | Không còn mật khẩu hay access key trong code và cấu hình; có alarm đã test; staging và production tách biệt. |
| 4 | [CI/CD](#tuần-4-cicd) | 9–15/11 | Merge vào `main` là tự build, test, deploy staging; production có bước duyệt, rollback trong 10 phút. |
| 5 | [IaC](#tuần-5-iac) | 16–22/11 | Xoá staging rồi dựng lại trong 30 phút chỉ bằng code và pipeline, không thao tác console. |
| 6 | [System design](#tuần-6-system-design) | 23/11–1/12 | Tài liệu thiết kế 3–5 trang cho 100.000 người dùng, bảo vệ được ở demo day 30/11–1/12. |

---

## Tuần 1: Docker

**19–25/10**

**Mốc tuần:** Người khác clone repo, chạy `docker compose up` là dùng được TeamBoard.

### Mục đích tuần 1

Đóng gói TeamBoard thành container để app chạy giống nhau trên mọi máy. Đây là nền cho cả khoá: tuần sau đưa lên AWS và tự động deploy đều dùng chính image này.

### Sau tuần này, mỗi người sẽ

- Hiểu image, container, layer; viết Dockerfile multi-stage gọn và build nhanh nhờ cache.
- Chạy nhiều service bằng Docker Compose: network, volume, health check.
- Quản lý cấu hình bằng biến môi trường, không để mật khẩu trong repo.
- Thêm cache Redis và đo được hiệu quả bằng số liệu.
- Dùng lệnh Docker và Linux cơ bản để tự debug container.

### Cuối tuần: đào sâu thêm

_Làm sau khi lab thứ Bảy đã đạt mốc. Chọn 1–2 mục, ghi điều học được vào log._

- Tối ưu image: chiseled/distroless, chạy non-root, quét lỗ hổng bằng `docker scout` hoặc Trivy.
- Docker networking sâu hơn: bridge network, DNS nội bộ giữa các container.
- Đọc 12-Factor App, tập trung các mục Config, Logs, Disposability.

### T2 19/10 · Dựng TeamBoard (2h)

**Mục tiêu:** Có Web API chạy local với CRUD cho Board và Task.

**Yêu cầu**

- ASP.NET Core Web API, project `src/TeamBoard.Api`.
- Entity `Board` (Id, Name, CreatedAt) và `TaskItem` (Id, BoardId, Title, Status, DueDate), quan hệ 1 Board – n Task.
- EF Core + SQL Server (LocalDB hoặc bản cài sẵn), migration `InitialCreate`.
- Endpoint `/api/boards`, `/api/boards/{id}/tasks`, `/api/tasks/{id}` đủ GET/POST/PUT/DELETE.
- Swagger bật ở Development.

**Output phải nộp**

- Repo `teamboard` trên GitHub, README có cách chạy.
- File `LEARNING_LOG.md` có mục đầu tiên.

**Tự đánh giá: đạt khi**

- `dotnet run` lên, `/swagger` thấy đủ endpoint.
- Tạo 1 board, 2 task; GET tasks của board trả đúng 2 task.
- Id không tồn tại trả 404; tạo task thiếu Title trả 400.
- Xoá board có task: xử lý nhất quán (xoá theo hoặc chặn), lý do ghi trong README.

_Nâng cao (không bắt buộc):_ DTO tách khỏi entity, validation bằng FluentValidation.

### T3 20/10 · Dockerfile multi-stage (2h)

**Mục tiêu:** Build được image của API và chạy trong container.

**Yêu cầu**

- Giải thích bằng lời của mình: image, container, layer, registry.
- Dockerfile 2 stage: build bằng `dotnet/sdk`, chạy bằng `dotnet/aspnet`.
- Copy `.csproj` và `dotnet restore` trước khi copy toàn bộ source.
- `.dockerignore` loại `bin/`, `obj/`, `.git`, `.env`.

**Output phải nộp**

- `Dockerfile`, `.dockerignore`.
- Log ghi kích thước image SDK và image runtime.

**Tự đánh giá: đạt khi**

- `docker build -t teamboard-api .` thành công.
- `docker run -p 8080:8080 teamboard-api` khởi động được app (endpoint cần DB lỗi là bình thường).
- Image runtime nhỏ hơn rõ rệt, có số MB trong log.
- Sửa 1 file `.cs` rồi build lại: bước restore hiện `CACHED`.

_Nâng cao (không bắt buộc):_ Chạy container bằng user không phải root; thử image chiseled/alpine và so kích thước.

### T4 21/10 · Cấu hình, health check, Compose (2h)

**Mục tiêu:** Chạy API + SQL Server cùng lúc bằng Docker Compose.

**Yêu cầu**

- Connection string đọc từ biến môi trường `ConnectionStrings__Default`.
- Endpoint `/health` dùng `AddHealthChecks()` kèm kiểm tra DB.
- `docker-compose.yml` có service `api`, `db` (SQL Server 2022), named volume cho dữ liệu.
- Mật khẩu SA đọc từ `.env` (không commit), commit kèm `.env.example`.

**Output phải nộp**

- `docker-compose.yml`, `.env.example`, endpoint `/health`.

**Tự đánh giá: đạt khi**

- `docker compose up -d` cho 2 container running.
- `/health` Healthy khi DB chạy, Unhealthy sau `docker compose stop db`.
- `docker compose down` rồi `up` lại: dữ liệu cũ vẫn còn.
- `.env` nằm trong `.gitignore`; repo không chứa mật khẩu thật.

_Nâng cao (không bắt buộc):_ Thêm `healthcheck` cho service `db` trong compose.

### T5 22/10 · Migration khi khởi động, Linux tối thiểu (2h)

**Mục tiêu:** Trên máy trắng, `docker compose up` là app dùng được ngay.

**Yêu cầu**

- Tự chạy migration khi khởi động, chỉ ở Development.
- Xử lý DB chưa sẵn sàng: `depends_on` + `condition: service_healthy`, hoặc `EnableRetryOnFailure`.
- Seed 1 board mẫu, không seed trùng ở lần sau.
- Dùng được `docker compose logs -f api`, `docker exec -it <container> sh`, `ls`, `cat`, `env`, `ps`.

**Output phải nộp**

- Code migration + seed.
- Log ghi 5 lệnh Docker/Linux đã dùng và tác dụng.

**Tự đánh giá: đạt khi**

- `docker compose down -v` rồi `up`: app tự tạo DB, có board mẫu, log không lỗi.
- Khởi động lần 2 không sinh board mẫu thứ hai.
- Lấy được biến môi trường của container bằng `docker exec … env`.
- Trả lời được: vì sao không tự chạy migration khi start trên production nhiều instance.

### T6 23/10 · Redis cache (2h)

**Mục tiêu:** Cache danh sách task của một board và đo được hiệu quả.

**Yêu cầu**

- Thêm service `redis`, dùng `IDistributedCache` (`Microsoft.Extensions.Caching.StackExchangeRedis`).
- Cache GET `/api/boards/{id}/tasks`, TTL 60 giây.
- Xoá cache khi tạo, sửa, xoá task của board đó.
- Đo thời gian phản hồi có/không cache (ví dụ `curl -w "%{time_total}"`).

**Output phải nộp**

- Code cache.
- Bảng đo trong log: ít nhất 5 lần gọi mỗi trường hợp.

**Tự đánh giá: đạt khi**

- Lần gọi thứ 2 không chạy câu SQL (xem log EF Core).
- Tạo task mới, GET ngay thấy task đó.
- Tắt Redis: ghi lại app xử lý thế nào và đề xuất cách đúng.

_Nâng cao (không bắt buộc):_ Viết 3 dòng về cache stampede.

### T7 24/10 · Lab: hoàn thiện để người khác chạy được (5h)

**Mục tiêu:** Đạt mốc tuần 1.

**Yêu cầu**

- README đủ: phần mềm cần cài, các bước chạy, biến môi trường, sơ đồ các container.
- Nhờ 1 người trong team clone và chạy thử, sửa mọi lỗi phát sinh.
- Dọn code, mở PR `week-1` → `main`.

**Output phải nộp**

- PR tuần 1: đã làm gì, ảnh `/health` và Swagger, vấn đề đã gặp.

**Tự đánh giá: đạt khi**

- Người khác chạy `cp .env.example .env` rồi `docker compose up`, dùng được app trong 10 phút, không phải hỏi.
- Lịch sử git không chứa mật khẩu thật.
- Tiêu chí bắt buộc của T2–T6 đều Xanh.

### CN 25/10 · Review PR (2h)

**Mục tiêu:** Góp ý cho người khác và hoàn thiện PR của mình.

**Yêu cầu**

- Review 1–2 PR được phân công, mỗi PR ít nhất 3 comment: 1 điểm tốt, 1 lỗi hoặc rủi ro, 1 đề xuất.
- Sửa PR của mình theo góp ý, ghi tổng kết tuần vào `LEARNING_LOG.md`.

**Output phải nộp**

- PR tuần 1 đã sửa theo góp ý.
- Tổng kết tuần trong log.

**Tự đánh giá: đạt khi**

- PR của mình được approve trước tối Chủ nhật.
- Đã review đủ PR được giao, comment cụ thể (chỉ vào dòng code hoặc lệnh), không chỉ “LGTM”.

---

## Tuần 2: AWS cơ bản

**26/10–1/11**

**Mốc tuần:** TeamBoard chạy trên AWS với URL public, dữ liệu lưu trên RDS.

### Mục đích tuần 2

Đưa TeamBoard lên cloud lần đầu. Tuần này tập trung vào 3 nền móng của mọi hệ thống trên AWS: danh tính (IAM), mạng (VPC) và dữ liệu (RDS).

### Sau tuần này, mỗi người sẽ

- Phân biệt region, Availability Zone, IaaS / PaaS / SaaS.
- Đọc và tự viết IAM policy theo nguyên tắc quyền tối thiểu.
- Hiểu VPC, subnet public/private, security group và vẽ được sơ đồ mạng.
- Tạo, kết nối, migration và tắt/bật RDS; biết chi phí theo giờ.
- Deploy container lên App Runner và kết nối RDS qua VPC connector.

### Cuối tuần: đào sâu thêm

_Làm sau khi lab thứ Bảy đã đạt mốc. Chọn 1–2 mục, ghi điều học được vào log._

- Đọc AWS Well-Architected, hai trụ cột Security và Cost Optimization.
- IAM sâu hơn: cách AWS đánh giá policy, permission boundary.
- Mạng: NAT gateway, VPC endpoint, khi nào cần cái nào.
- Học khoá miễn phí Cloud Practitioner Essentials trên AWS Skill Builder.

### T2 26/10 · Khái niệm cloud, đăng nhập sandbox (1,5h)

**Mục tiêu:** Vào được tài khoản sandbox an toàn và hiểu khái niệm nền.

**Yêu cầu**

- Đăng nhập console, bật MFA cho user của mình.
- Xem AWS Budgets: ngưỡng cảnh báo và người nhận.
- Phân biệt region, Availability Zone, IaaS / PaaS / SaaS.

**Output phải nộp**

- Log: region team dùng và lý do; bảng 2 dịch vụ AWS cho mỗi loại IaaS, PaaS, SaaS.

**Tự đánh giá: đạt khi**

- Trang IAM của user mình hiện MFA đã gán.
- Giải thích được vì sao hệ thống chạy trên 2 AZ vẫn sống khi 1 AZ sự cố.
- Biết cảnh báo chi phí gửi tới ai, ở ngưỡng bao nhiêu.

### T3 27/10 · IAM và AWS CLI (1,5h)

**Mục tiêu:** Dùng AWS CLI với quyền tối thiểu và đọc được một policy.

**Yêu cầu**

- Hiểu user, group, role, policy; cấu trúc `Effect`, `Action`, `Resource`, `Condition`.
- Cài AWS CLI v2, cấu hình profile `teamboard` theo cách sandbox cấp.
- Tự viết policy chỉ cho đọc object trong một bucket S3 cụ thể.

**Output phải nộp**

- `docs/iam-notes.md`: policy tự viết kèm giải thích từng dòng.

**Tự đánh giá: đạt khi**

- `aws sts get-caller-identity --profile teamboard` trả đúng account và user.
- Access key (nếu có) chỉ nằm trong `~/.aws`, không có trong repo.
- Policy không dùng `"*"` cho `Action`, `Resource` là ARN cụ thể.
- Giải thích được khác nhau giữa user và role.

### T4 28/10 · Mạng VPC (1,5h)

**Mục tiêu:** Hiểu mạng mà app và database sẽ chạy bên trong.

**Yêu cầu**

- Xem VPC sandbox: CIDR, subnet public/private, route table, internet gateway.
- Phân biệt security group và network ACL.
- Vẽ sơ đồ: VPC, 2 AZ, subnet public/private, vị trí RDS, đường App Runner kết nối vào.

**Output phải nộp**

- `docs/network.png` (kèm file gốc) và 5 dòng giải thích.

**Tự đánh giá: đạt khi**

- Sơ đồ có CIDR, ít nhất 2 AZ, subnet public/private, internet gateway.
- Security group của RDS chỉ mở cổng 1433 cho nguồn cần thiết.
- Nói được subnet public và private khác nhau ở đâu.

### T5 29/10 · Database trên RDS (1,5h)

**Mục tiêu:** TeamBoard có database trên RDS.

**Yêu cầu**

- Tạo RDS SQL Server Express, instance nhỏ nhất sandbox cho phép, trong subnet private.
- Kết nối từ máy mình theo hướng dẫn của mentor (bastion hoặc cách sandbox hỗ trợ).
- Chạy migration từ local vào RDS.
- Stop instance khi xong (RDS stop sẽ tự bật lại sau 7 ngày).

**Output phải nộp**

- Log: endpoint RDS (không ghi mật khẩu), ảnh rule security group, chi phí ước tính mỗi giờ.

**Tự đánh giá: đạt khi**

- Kết nối được bằng SSMS hoặc Azure Data Studio, thấy bảng `Boards` và `TaskItems`.
- Security group không có rule `0.0.0.0/0`.
- Instance ở trạng thái Stopped sau buổi học.

### T6 30/10 · Đưa image lên ECR (1,5h)

**Mục tiêu:** Image TeamBoard nằm trên ECR, sẵn sàng deploy.

**Yêu cầu**

- Tạo repository ECR `teamboard-api`, bật scan on push.
- Đăng nhập Docker vào ECR bằng `aws ecr get-login-password`, tag theo version, push.
- Lifecycle policy giữ 10 image gần nhất.
- Máy Mac chip Apple: build với `--platform linux/amd64`.

**Output phải nộp**

- URI image trong log; số lỗ hổng High/Critical từ kết quả scan.

**Tự đánh giá: đạt khi**

- `aws ecr describe-images --repository-name teamboard-api` thấy image vừa push.
- Image có tag version, không chỉ `latest`.
- Đã đọc kết quả scan và ghi số liệu vào log.

### T7 31/10 · Lab: app live trên App Runner (3h)

**Mục tiêu:** Đạt mốc tuần 2.

**Yêu cầu**

- App Runner service từ image ECR, port 8080, health check `/health`.
- Kết nối RDS qua VPC connector; security group RDS cho phép security group của connector.
- Connection string tạm qua biến môi trường (tuần 3 chuyển sang Secrets Manager).
- Cập nhật `docs/network.png`, mở PR `week-2`.

**Output phải nộp**

- URL public, PR tuần 2, chi phí ước tính mỗi ngày.

**Tự đánh giá: đạt khi**

- `<URL>/health` trả Healthy.
- Tạo board qua URL public, thấy dữ liệu trên RDS.
- App Runner báo Running, không restart liên tục.
- RDS vẫn không mở ra internet.

### CN 1/11 · Review PR (1,5h)

**Mục tiêu:** Góp ý cho người khác và hoàn thiện PR của mình.

**Yêu cầu**

- Review 1–2 PR được phân công, mỗi PR ít nhất 3 comment: 1 điểm tốt, 1 lỗi hoặc rủi ro, 1 đề xuất.
- Kiểm tra riêng: có lộ thông tin nhạy cảm không, security group có mở quá rộng không.
- Sửa PR của mình theo góp ý, ghi tổng kết tuần vào `LEARNING_LOG.md`.

**Output phải nộp**

- PR tuần 2 đã sửa theo góp ý.
- Tổng kết tuần trong log.

**Tự đánh giá: đạt khi**

- PR của mình được approve trước tối Chủ nhật.
- Đã review đủ PR được giao, comment cụ thể (chỉ vào dòng code hoặc lệnh), không chỉ “LGTM”.

---

## Tuần 3: AWS vận hành

**2–8/11**

**Mốc tuần:** Không còn mật khẩu hay access key trong code và cấu hình; có alarm đã test; staging và production tách biệt.

### Mục đích tuần 3

Biến app “chạy được” thành app “vận hành được”: không lộ secret, lưu file đúng cách, nhìn thấy lỗi và được báo ngay khi có sự cố.

### Sau tuần này, mỗi người sẽ

- Quản lý secret bằng Secrets Manager; app dùng IAM role thay cho access key.
- Lưu file trên S3 private và cấp quyền tạm bằng presigned URL.
- Structured logging và truy vấn log bằng CloudWatch Logs Insights.
- Dựng alarm + SNS, chọn ngưỡng cảnh báo có lý do.
- Tách staging/production và cấu hình auto scaling.

### Cuối tuần: đào sâu thêm

_Làm sau khi lab thứ Bảy đã đạt mốc. Chọn 1–2 mục, ghi điều học được vào log._

- Tracing phân tán với OpenTelemetry / AWS X-Ray.
- Chạy thử trên ECS Fargate và so sánh với App Runner.
- S3 nâng cao: versioning, lifecycle, CloudFront.
- Đọc về SLI/SLO trong Google SRE Book (chương Service Level Objectives).

### T2 2/11 · Secrets Manager (1,5h)

**Mục tiêu:** Thông tin kết nối DB nằm trong Secrets Manager thay vì cấu hình.

**Yêu cầu**

- Tạo secret `teamboard/staging/db` chứa connection string.
- Đọc secret bằng `aws secretsmanager get-secret-value`.
- Hiểu rotation và vì sao không copy giá trị secret ra chỗ khác.

**Output phải nộp**

- ARN của secret trong log (không ghi giá trị).

**Tự đánh giá: đạt khi**

- Đọc được secret bằng CLI với profile của mình.
- Log và repo không chứa giá trị secret.
- Giải thích được rotation trong 3 dòng.

### T3 3/11 · IAM role cho App Runner (1,5h)

**Mục tiêu:** App lấy secret bằng role, không cần access key nào.

**Yêu cầu**

- Instance role có `secretsmanager:GetSecretValue` chỉ trên ARN của secret.
- Biến `ConnectionStrings__Default` của App Runner tham chiếu tới secret.
- Xoá mọi connection string dạng chữ thường còn sót.

**Output phải nộp**

- `docs/iam-roles.md`: role, policy, lý do từng quyền.

**Tự đánh giá: đạt khi**

- Cấu hình App Runner không có mật khẩu dạng chữ thường.
- Đổi mật khẩu trong secret và RDS, deploy lại: app vẫn chạy.
- `Resource` của policy là ARN cụ thể.
- Tìm `AKIA` trong repo không ra kết quả.

### T4 4/11 · S3 và presigned URL (1,5h)

**Mục tiêu:** Task đính kèm được file, file lưu trên S3 private.

**Yêu cầu**

- Bucket private `teamboard-attachments-<tên>`, bật Block Public Access.
- `POST /api/tasks/{id}/attachments/upload-url` trả presigned PUT URL, hết hạn 5–15 phút.
- `GET /api/attachments/{id}/download-url` trả presigned URL tải về.
- Metadata lưu bảng `Attachments`; instance role chỉ có quyền trên bucket này.

**Output phải nộp**

- Code 2 endpoint, migration `Attachments`, lệnh curl test trong log.

**Tự đánh giá: đạt khi**

- Upload bằng `curl -X PUT --upload-file` thành công, tải về đúng file.
- URL hết hạn trả 403.
- Mở URL object không ký trả Access Denied.

_Nâng cao (không bắt buộc):_ Giới hạn loại file và kích thước tối đa.

### T5 5/11 · CloudWatch Logs, structured logging (1,5h)

**Mục tiêu:** Đọc và truy vấn được log của app trên CloudWatch.

**Yêu cầu**

- Log dạng JSON ra console (Serilog hoặc JSON console logger).
- Mỗi request log method, path, status code, thời gian xử lý, trace id.
- 2 câu truy vấn Logs Insights: 5 endpoint chậm nhất; số lỗi 5xx theo giờ.

**Output phải nộp**

- `docs/observability.md` có 2 câu truy vấn và ảnh kết quả.

**Tự đánh giá: đạt khi**

- Log trên CloudWatch là JSON, lọc được theo `StatusCode`.
- 2 câu truy vấn chạy ra kết quả đúng.
- Log không chứa connection string, token hay nội dung file.

### T6 6/11 · Alarm và thông báo (1,5h)

**Mục tiêu:** Nhận được email khi app lỗi nhiều.

**Yêu cầu**

- SNS topic gửi email, đã xác nhận đăng ký.
- Alarm trên metric lỗi 5xx của App Runner, vượt ngưỡng trong 5 phút thì báo.
- Endpoint `/api/debug/error` trả 500, chỉ bật ở staging.

**Output phải nộp**

- Ảnh email alarm; ngưỡng và lý do trong log.

**Tự đánh giá: đạt khi**

- Gọi endpoint lỗi liên tục: email alarm đến.
- Ngừng gọi: alarm tự về OK.
- Endpoint lỗi không tồn tại ở production.

### T7 7/11 · Lab: tách staging/production (3h)

**Mục tiêu:** Đạt mốc tuần 3.

**Yêu cầu**

- 2 service `teamboard-staging` và `teamboard-prod`, mỗi service một secret và một database riêng.
- Auto scaling: min 1, max 2–3, giới hạn concurrency; ghi lý do.
- Vẽ sơ đồ hạ tầng đầy đủ, mở PR `week-3`.

**Output phải nộp**

- `docs/architecture.png`, 2 URL, PR tuần 3.

**Tự đánh giá: đạt khi**

- Dữ liệu tạo ở staging không xuất hiện ở production.
- `git log -p` toàn repo không chứa mật khẩu hay access key.
- Alarm đã test ở staging; sơ đồ khớp hạ tầng thật.

_Nâng cao (không bắt buộc):_ Chạy cùng image trên ECS Fargate và so sánh.

### CN 8/11 · Review PR (1,5h)

**Mục tiêu:** Góp ý cho người khác và hoàn thiện PR của mình.

**Yêu cầu**

- Review 1–2 PR được phân công, mỗi PR ít nhất 3 comment: 1 điểm tốt, 1 lỗi hoặc rủi ro, 1 đề xuất.
- Kiểm tra riêng: policy có quá rộng không, log có lộ dữ liệu nhạy cảm không.
- Sửa PR của mình theo góp ý, ghi tổng kết tuần vào `LEARNING_LOG.md`.

**Output phải nộp**

- PR tuần 3 đã sửa theo góp ý.
- Tổng kết tuần trong log.

**Tự đánh giá: đạt khi**

- PR của mình được approve trước tối Chủ nhật.
- Đã review đủ PR được giao, comment cụ thể (chỉ vào dòng code hoặc lệnh), không chỉ “LGTM”.

---

## Tuần 4: CI/CD

**9–15/11**

**Mốc tuần:** Merge vào `main` là tự build, test, deploy staging; production có bước duyệt, rollback trong 10 phút.

### Mục đích tuần 4

Tự động hoá con đường từ code đến production, để mỗi lần deploy là việc nhỏ, an toàn và lặp lại được.

### Sau tuần này, mỗi người sẽ

- Viết workflow GitHub Actions để build và test mỗi PR.
- Viết unit test và bảo vệ nhánh `main`.
- Kết nối GitHub với AWS qua OIDC, không lưu access key.
- Build, tag image theo commit SHA, tự deploy staging kèm smoke test.
- Quy trình duyệt production và rollback nhanh.

### Cuối tuần: đào sâu thêm

_Làm sau khi lab thứ Bảy đã đạt mốc. Chọn 1–2 mục, ghi điều học được vào log._

- Chiến lược deploy: blue/green, canary, feature flag.
- Reusable workflow và matrix build trong GitHub Actions.
- Bảo mật pipeline: Dependabot, quét secret, ký image.
- Đọc về 4 chỉ số DORA (sách Accelerate).

### T2 9/11 · Workflow CI đầu tiên (1,5h)

**Mục tiêu:** Mỗi PR tự động được build và test.

**Yêu cầu**

- Hiểu workflow, job, step, runner, trigger.
- `.github/workflows/ci.yml` chạy khi `pull_request`: checkout, setup-dotnet, restore, build, test.
- Cache NuGet package.

**Output phải nộp**

- `ci.yml`, link một lần chạy thành công.

**Tự đánh giá: đạt khi**

- PR hiển thị check xanh.
- Cố ý làm code không build được: check chuyển đỏ.
- Lần chạy thứ 2 có cache hit, ghi thời gian 2 lần.

### T3 10/11 · Unit test và bảo vệ nhánh main (1,5h)

**Mục tiêu:** Có bộ test tối thiểu, không ai đẩy thẳng vào `main`.

**Yêu cầu**

- `tests/TeamBoard.Tests` dùng xUnit, 5–10 test cho phần nghiệp vụ.
- SQLite in-memory hoặc mock cho phần dữ liệu.
- Branch protection `main`: bắt buộc PR, CI pass, ít nhất 1 approval.

**Output phải nộp**

- Project test, ảnh cấu hình branch protection.

**Tự đánh giá: đạt khi**

- `dotnet test` pass ở local và CI.
- Sửa sai một điều kiện: ít nhất 1 test đỏ.
- `git push` thẳng lên `main` bị từ chối.

_Nâng cao (không bắt buộc):_ Đo code coverage và hiện trong kết quả CI.

### T4 11/11 · GitHub Actions → AWS qua OIDC (1,5h)

**Mục tiêu:** Pipeline gọi được AWS mà không lưu access key ở GitHub.

**Yêu cầu**

- IAM OIDC provider cho `token.actions.githubusercontent.com`.
- Role `github-actions-teamboard`, trust policy giới hạn đúng repo (điều kiện `sub`).
- Workflow có `permissions: id-token: write`, dùng `aws-actions/configure-aws-credentials`, chạy `aws sts get-caller-identity`.

**Output phải nộp**

- Trust policy trong `docs/iam-roles.md`, link lần chạy in ra role ARN.

**Tự đánh giá: đạt khi**

- Job in đúng ARN của role.
- GitHub Secrets không chứa AWS access key.
- Trust policy không cho repo khác.
- Giải thích được vì sao OIDC an toàn hơn lưu key.

### T5 12/11 · Build và push image trong pipeline (1,5h)

**Mục tiêu:** Mỗi commit trên `main` có một image tương ứng trên ECR.

**Yêu cầu**

- `deploy.yml` chạy khi push `main`: build, tag commit SHA, push ECR.
- Endpoint `/version` trả commit SHA.
- Role pipeline chỉ được push vào repo `teamboard-api`.

**Output phải nộp**

- `deploy.yml`, danh sách image có tag SHA.

**Tự đánh giá: đạt khi**

- 2 commit liên tiếp tạo 2 image với 2 tag SHA khác nhau.
- Test fail thì không push image.
- Chạy image local, `/version` trả đúng SHA.

### T6 13/11 · Tự động deploy staging (1,5h)

**Mục tiêu:** Merge là staging chạy code mới, không thao tác tay.

**Yêu cầu**

- Job deploy cập nhật image của `teamboard-staging` và chờ deploy xong.
- Smoke test `/health` và `/version`; sai SHA hoặc không Healthy thì job fail.

**Output phải nộp**

- Link một lần pipeline chạy trọn từ merge đến staging.

**Tự đánh giá: đạt khi**

- Merge PR, trong 15 phút `/version` staging trả SHA mới.
- Cố ý làm `/health` lỗi: pipeline đỏ ở bước smoke test.

### T7 14/11 · Lab: duyệt production và rollback (3h)

**Mục tiêu:** Đạt mốc tuần 4.

**Yêu cầu**

- GitHub Environment `production` có required reviewer.
- Workflow rollback (`workflow_dispatch`) nhận tag SHA và deploy lại image đó.
- Diễn tập: deploy bản lỗi, phát hiện, rollback, bấm giờ.
- Mở PR `week-4`.

**Output phải nộp**

- PR tuần 4, link pipeline có bước duyệt, thời gian rollback.

**Tự đánh giá: đạt khi**

- Production không đổi khi chưa ai duyệt.
- Rollback xong trong 10 phút, `/version` trả SHA cũ.
- Không thao tác trên console AWS.

### CN 15/11 · Review PR (1,5h)

**Mục tiêu:** Góp ý cho người khác và hoàn thiện PR của mình.

**Yêu cầu**

- Review 1–2 PR được phân công, mỗi PR ít nhất 3 comment: 1 điểm tốt, 1 lỗi hoặc rủi ro, 1 đề xuất.
- Kiểm tra riêng: quyền của role pipeline, trust policy, bước smoke test.
- Sửa PR của mình theo góp ý, ghi tổng kết tuần vào `LEARNING_LOG.md`.

**Output phải nộp**

- PR tuần 4 đã sửa theo góp ý.
- Tổng kết tuần trong log.

**Tự đánh giá: đạt khi**

- PR của mình được approve trước tối Chủ nhật.
- Đã review đủ PR được giao, comment cụ thể (chỉ vào dòng code hoặc lệnh), không chỉ “LGTM”.

---

## Tuần 5: IaC

**16–22/11**

**Mốc tuần:** Xoá staging rồi dựng lại trong 30 phút chỉ bằng code và pipeline, không thao tác console.

### Mục đích tuần 5

Mô tả toàn bộ hạ tầng bằng code để dựng lại được bất cứ lúc nào, và tập xử lý sự cố giống như trên dự án thật.

### Sau tuần này, mỗi người sẽ

- Dùng AWS CDK viết bằng C#, hiểu quan hệ với CloudFormation.
- Viết stack cho ECR, S3, RDS, Secrets Manager, App Runner.
- Đưa thay đổi hạ tầng qua PR với `cdk diff` trong pipeline.
- Migration database tương thích ngược, tách khỏi lúc app khởi động.
- Điều tra sự cố bằng log/alarm và viết incident note không đổ lỗi.

### Cuối tuần: đào sâu thêm

_Làm sau khi lab thứ Bảy đã đạt mốc. Chọn 1–2 mục, ghi điều học được vào log._

- Viết lại một phần bằng Terraform và so sánh với CDK.
- Test cho CDK (assertions) và kiểm tra bảo mật bằng cdk-nag.
- Phát hiện drift giữa code và hạ tầng thật.
- Đọc chương Postmortem Culture trong Google SRE Book.

### T2 16/11 · Làm quen AWS CDK (1,5h)

**Mục tiêu:** Deploy và xoá được một stack đơn giản bằng CDK viết bằng C#.

**Yêu cầu**

- Cài Node.js và CDK CLI (`npm install -g aws-cdk`).
- Trong `infra/`: `cdk init app --language csharp`, `cdk bootstrap` nếu cần.
- Stack thử 1 bucket S3: chạy `cdk synth`, `cdk diff`, `cdk deploy`, `cdk destroy`.

**Output phải nộp**

- Project `infra/`, log ghi tác dụng 4 lệnh.

**Tự đánh giá: đạt khi**

- Thấy stack trong CloudFormation sau deploy, mất sau destroy.
- `cdk diff` hiện thay đổi trước khi deploy.
- Giải thích được `cdk synth` sinh ra gì.

### T3 17/11 · CDK: ECR và S3 (1,5h)

**Mục tiêu:** ECR và bucket đính kèm được quản lý bằng code.

**Yêu cầu**

- Stack `TeamBoardStaging`: ECR (scan, lifecycle 10 image) và S3 (Block Public Access, mã hoá, xoá được khi destroy).
- Tag `Project=TeamBoard`, `Env=staging` cho mọi tài nguyên.
- Tên tài nguyên đọc từ cấu hình theo môi trường.

**Output phải nộp**

- Code stack, kết quả `cdk diff` trong log.

**Tự đánh giá: đạt khi**

- Mọi tài nguyên có đủ tag.
- Deploy xong chạy lại `cdk diff`: không còn thay đổi.
- Bucket không truy cập công khai được.

### T4 18/11 · CDK: RDS, Secrets Manager, App Runner (1,5h)

**Mục tiêu:** Toàn bộ hạ tầng staging nằm trong code.

**Yêu cầu**

- RDS trong subnet private, mật khẩu do CDK sinh, lưu Secrets Manager.
- App Runner (L1 `CfnService` hoặc module alpha), VPC connector, instance role, tham chiếu secret.
- Stack output URL của service.

**Output phải nộp**

- Code stack hoàn chỉnh cho staging.

**Tự đánh giá: đạt khi**

- Code CDK không chứa mật khẩu.
- `cdk deploy` in ra URL, `/health` Healthy.
- Security group RDS chỉ cho phép VPC connector.

### T5 19/11 · Chạy CDK trong pipeline (1,5h)

**Mục tiêu:** Mọi thay đổi hạ tầng đi qua PR và pipeline.

**Yêu cầu**

- Job `infra` chạy `cdk diff` trên PR có thay đổi trong `infra/`.
- Merge vào `main`: `cdk deploy` staging trước bước deploy app.
- Role OIDC riêng cho infra.

**Output phải nộp**

- Workflow cập nhật, link lần chạy có `cdk diff` trên PR.

**Tự đánh giá: đạt khi**

- Đổi 1 thuộc tính qua PR: thấy diff ở PR, merge xong hạ tầng đổi đúng.
- Role infra và role app là 2 role khác nhau.

### T6 20/11 · Migration database an toàn (1,5h)

**Mục tiêu:** Migration chạy thành bước riêng, không chạy lúc app khởi động ở staging/production.

**Yêu cầu**

- `dotnet ef migrations bundle`, chạy trong pipeline trước deploy app.
- Tắt tự chạy migration khi start ngoài Development.
- Thêm cột `Priority` theo kiểu tương thích ngược.

**Output phải nộp**

- Bước migration trong pipeline; log giải thích cách xử lý khi migration lỗi giữa chừng.

**Tự đánh giá: đạt khi**

- Log khởi động staging không còn dòng chạy migration.
- Bản app cũ vẫn chạy được với DB mới trong lúc chuyển.
- Nêu được 1 ví dụ migration không rollback được và cách xử lý.

### T7 21/11 · Lab: dựng lại môi trường, diễn tập sự cố (3h)

**Mục tiêu:** Đạt mốc tuần 5.

**Yêu cầu**

- `cdk destroy` staging rồi dựng lại chỉ bằng pipeline/lệnh, bấm giờ.
- Diễn tập sự cố theo kịch bản mentor giao, chỉ dùng log, alarm, pipeline.
- Incident note: timeline, dấu hiệu, nguyên nhân, cách sửa, phòng ngừa.
- Mở PR `week-5`.

**Output phải nộp**

- `docs/incident-<ngày>.md`, thời gian dựng lại, PR tuần 5.

**Tự đánh giá: đạt khi**

- Staging dựng lại trong 30 phút, `/health` Healthy, không thao tác console.
- Tìm ra nguyên nhân bằng log hoặc alarm, không phải đoán.
- Incident note không đổ lỗi, có ít nhất 1 hành động phòng ngừa cụ thể.

_Nâng cao (không bắt buộc):_ Viết lại một phần hạ tầng bằng Terraform và so sánh.

### CN 22/11 · Review PR (1,5h)

**Mục tiêu:** Góp ý cho người khác và hoàn thiện PR của mình.

**Yêu cầu**

- Review 1–2 PR được phân công, mỗi PR ít nhất 3 comment: 1 điểm tốt, 1 lỗi hoặc rủi ro, 1 đề xuất.
- Kiểm tra riêng: code CDK có viết cứng giá trị nào không, incident note có rõ ràng không.
- Sửa PR của mình theo góp ý, ghi tổng kết tuần vào `LEARNING_LOG.md`.

**Output phải nộp**

- PR tuần 5 đã sửa theo góp ý.
- Tổng kết tuần trong log.

**Tự đánh giá: đạt khi**

- PR của mình được approve trước tối Chủ nhật.
- Đã review đủ PR được giao, comment cụ thể (chỉ vào dòng code hoặc lệnh), không chỉ “LGTM”.

---

## Tuần 6: System design

**23/11–1/12**

**Mốc tuần:** Tài liệu thiết kế 3–5 trang cho 100.000 người dùng, bảo vệ được ở demo day 30/11–1/12.

### Mục đích tuần 6

Nhìn TeamBoard ở quy mô 100.000 người dùng: ước lượng tải, chọn kiến trúc, cân nhắc đánh đổi và trình bày được quyết định của mình trước team.

### Sau tuần này, mỗi người sẽ

- Ước lượng tải và dung lượng bằng số liệu có giả định rõ ràng.
- Thiết kế index, cache, read replica cho bài toán thật.
- Xử lý bất đồng bộ với queue, DLQ và idempotency.
- Viết yêu cầu phi chức năng đo được và kiến trúc đáp ứng chúng.
- Viết quyết định thiết kế (ADR), ước chi phí, trình bày và bảo vệ thiết kế.

### Cuối tuần: đào sâu thêm

_Làm sau khi lab thứ Bảy đã đạt mốc. Chọn 1–2 mục, ghi điều học được vào log._

- System Design Interview (Alex Xu) hoặc các bài trên ByteByteGo.
- Designing Data-Intensive Applications, chương Replication và Partitioning.
- Tự luyện thiết kế 1 hệ thống quen thuộc: rút gọn URL, chat, đặt vé.
- Kiến trúc hướng sự kiện với Amazon EventBridge.

### T2 23/11 · Scalability và ước lượng tải (2h)

**Mục tiêu:** Ước lượng tải của hệ thống bằng số liệu cụ thể.

**Yêu cầu**

- Đọc: scale dọc/ngang, stateless service, load balancer.
- Ước lượng cho 100.000 người dùng: tỷ lệ dùng hằng ngày, request mỗi người, QPS trung bình và cao điểm, dung lượng DB và file sau 1 năm.

**Output phải nộp**

- `docs/design/capacity.md`: giả định, công thức, kết quả.

**Tự đánh giá: đạt khi**

- Mọi con số có giả định và cách tính.
- Chỉ ra thành phần nghẽn đầu tiên và vì sao.

### T3 24/11 · Database và cache ở quy mô lớn (2h)

**Mục tiêu:** Biết khi nào dùng index, read replica, chia dữ liệu và cache.

**Yêu cầu**

- Đề xuất 3 index cho truy vấn chính (task theo board, theo status, theo hạn).
- Execution plan trước/sau index trên DB local có ~100.000 task giả.
- Chiến lược cache cho 2 endpoint: TTL, xoá cache, xử lý khi cache sập.

**Output phải nộp**

- `docs/design/data.md` kèm ảnh execution plan.

**Tự đánh giá: đạt khi**

- Execution plan chuyển từ scan sang seek, có số đo thời gian.
- Nêu được vấn đề của read replica với dữ liệu vừa ghi và cách xử lý.

### T4 25/11 · Messaging với SQS/SNS (2h)

**Mục tiêu:** Xử lý bất đồng bộ qua queue, chịu được lỗi và message trùng.

**Yêu cầu**

- Thêm `AssigneeEmail` cho task; giao task thì API gửi message vào SQS.
- Worker `BackgroundService` (chạy local) đọc message, ghi log “đã gửi thông báo”.
- DLQ sau 3 lần lỗi; xử lý idempotent.

**Output phải nộp**

- Code worker, kịch bản test và kết quả trong log.

**Tự đánh giá: đạt khi**

- Tắt worker, gửi 10 message, bật lại: xử lý đủ 10.
- Message lỗi nằm trong DLQ sau 3 lần thử.
- Gửi lặp cùng message: chỉ 1 thông báo.

### T5 26/11 · Monolith hay microservices, nhận đề capstone (2h)

**Mục tiêu:** Viết được yêu cầu có số đo cho đề capstone.

**Yêu cầu**

- Đọc: API gateway, idempotency, retry với backoff, circuit breaker; khi nào chưa nên tách microservice.
- Đề: TeamBoard cho 100.000 người dùng, thông báo realtime, báo cáo.
- Ít nhất 5 yêu cầu chức năng và 4 yêu cầu phi chức năng.

**Output phải nộp**

- `docs/design/requirements.md`.

**Tự đánh giá: đạt khi**

- Mỗi yêu cầu phi chức năng có con số đo được (ví dụ p95 dưới 300 ms, sẵn sàng 99,9%).
- Ghi rõ điều nằm ngoài phạm vi.

### T6 27/11 · Kiến trúc tổng thể (2h)

**Mục tiêu:** Có sơ đồ kiến trúc đáp ứng mọi yêu cầu hôm qua.

**Yêu cầu**

- Sơ đồ thành phần và dịch vụ AWS cho từng thành phần.
- Luồng dữ liệu cho: tạo task, nhận thông báo realtime.
- Bảng đối chiếu yêu cầu phi chức năng ↔ thành phần đáp ứng.

**Output phải nộp**

- `docs/design/architecture.md` + sơ đồ.

**Tự đánh giá: đạt khi**

- Không yêu cầu phi chức năng nào bị bỏ trống trong bảng đối chiếu.
- Mọi thành phần trong sơ đồ giải thích được vì sao cần.

### T7 28/11 · Quyết định thiết kế, chi phí, hoàn thiện tài liệu (5h)

**Mục tiêu:** Tài liệu thiết kế hoàn chỉnh, sẵn sàng bảo vệ.

**Yêu cầu**

- 3 quyết định thiết kế: bối cảnh, các phương án, phương án chọn, hệ quả và đánh đổi.
- Chi phí hằng tháng bằng AWS Pricing Calculator.
- Gộp tài liệu 3–5 trang, tập trình bày 10 phút có bấm giờ.

**Output phải nộp**

- `docs/design/design.md` (hoặc PDF), link ước tính chi phí, PR `week-6`.

**Tự đánh giá: đạt khi**

- Mỗi quyết định có ít nhất 2 phương án và nêu rõ đánh đổi.
- Chi phí có link Pricing Calculator và giả định.
- Bài tập trình bày không quá 10 phút.

### CN 29/11 · Review chéo tài liệu (2h)

**Mục tiêu:** Tài liệu được phản biện trước demo day.

**Yêu cầu**

- Đọc 2 tài liệu được giao, mỗi tài liệu 3 câu hỏi phản biện dưới dạng comment trên PR.
- Sửa tài liệu của mình theo câu hỏi nhận được, nộp bản cuối.

**Output phải nộp**

- Bản cuối tài liệu thiết kế đã merge.

**Tự đánh giá: đạt khi**

- Đã trả lời hoặc xử lý mọi câu hỏi phản biện nhận được.
- Bản cuối merge trước tối Chủ nhật.

### T2–T3 30/11–1/12 · Demo day: tiêu chí chấm

Mỗi người 10 phút trình bày + 5 phút phản biện, 4 người mỗi buổi. Mỗi tiêu chí 1–3 điểm; đạt khi tổng từ 10/15 và không tiêu chí nào 1 điểm.

**3 điểm khi**

- **Yêu cầu:** Mọi yêu cầu phi chức năng đo được, phạm vi rõ
- **Kiến trúc:** Đáp ứng đủ, mỗi thành phần có lý do
- **Quyết định thiết kế:** So sánh rõ, đánh đổi có số liệu
- **Chi phí:** Có số, giả định và cách giảm chi phí
- **Trả lời phản biện:** Trả lời chắc, thừa nhận điểm yếu và hướng xử lý
