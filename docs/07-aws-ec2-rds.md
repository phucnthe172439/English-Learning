# 07 · Deploy API lên AWS: EC2 có sẵn + RDS + Secrets Manager

Hướng dẫn này đưa **API** của English-Learning lên **EC2 bạn đã tạo sẵn** (Amazon Linux 2023), chuyển database sang **RDS for SQL Server**, và lưu mọi mật khẩu trong **AWS Secrets Manager**.

Phần lớn các bước làm trên **AWS Management Console** (giao diện web). Câu lệnh chỉ dùng ở những chỗ console không làm được: build/push image bằng Docker và chạy container trên EC2.

> Trước khi bắt đầu, bạn cần chạy được project ở máy bằng `docker compose up` ([04-database-docker.md](04-database-docker.md)).
>
> Hướng dẫn này chỉ deploy API. Frontend làm ở bước sau (xem [§11](#11-bước-tiếp-theo)).

**Mỗi bước có nhãn cho biết làm ở đâu:**

| Nhãn | Làm ở đâu |
|---|---|
| 🌐 **Console** | Trình duyệt, tại https://console.aws.amazon.com |
| 💻 **PC** | PowerShell trên máy bạn |
| 🐧 **EC2** | Terminal của EC2. Mở bằng **EC2 Instance Connect** ngay trên console (§3.3), hoặc SSH |

**Quy ước** (thay bằng giá trị thật của bạn):

| Ký hiệu | Ý nghĩa | Ví dụ |
|---|---|---|
| `<USER>` | User đăng nhập EC2 | `ec2-server` |
| `<EC2-PUBLIC-IP>` | Public IPv4 của EC2 | `13.212.x.x` |
| `<EC2-SG>` | Security group đang gắn với EC2 | `launch-wizard-1` |
| `<ACCOUNT-ID>` | Số tài khoản AWS (12 chữ số), xem ở góc trên bên phải console | `123456789012` |

---

## 1. Kiến trúc

```
                         Internet
                            │  http://<EC2-PUBLIC-IP>/health
                            ▼
┌──────────────────────── VPC ───────────────────────────────────────┐
│                                                                    │
│  ┌──────── EC2 có sẵn (Amazon Linux 2023) ──┐                      │
│  │  sg: <EC2-SG>                            │                      │
│  │  IAM role: english-ec2-role ─────────────┼──► ECR (pull image)  │
│  │                              ├───────────┼──► Secrets Manager   │
│  │                              └───────────┼──► S3 (script SQL)   │
│  │  ┌─────────────┐   ┌──────────────┐      │                      │
│  │  │ english-api │──►│ redis        │      │                      │
│  │  │ :80 → 8080  │   │ (không mở    │      │                      │
│  │  │             │   │  port ra)    │      │                      │
│  │  └──────┬──────┘   └──────────────┘      │                      │
│  └─────────┼────────────────────────────────┘                      │
│            │ 1433 (chỉ từ <EC2-SG>)                                │
│            ▼                                                       │
│  ┌──────── RDS for SQL Server ──────────────┐                      │
│  │  sg: english-rds-sg, KHÔNG public         │                     │
│  │  DB: EnglishVocabularyTraining            │                     │
│  └───────────────────────────────────────────┘                     │
└────────────────────────────────────────────────────────────────────┘
```

| Ở máy (docker compose) | Trên AWS | Lý do |
|---|---|---|
| Container `db` | **RDS for SQL Server** | AWS lo backup, vá lỗi, ổ đĩa; EC2 có chết thì data vẫn còn |
| Container `db-init` | Chạy 3 script SQL **một lần** từ EC2 (§8.3) | RDS không public, chỉ EC2 kết nối được |
| `SA_PASSWORD` trong `.env` | **Mật khẩu master của RDS**, do RDS tự tạo và lưu vào Secrets Manager | Bạn không cần nhìn thấy hay gõ nó |
| `APP_DB_PASSWORD` trong `.env` | Secret **`english-learning/prod/db`** trong Secrets Manager | API đọc khi khởi động |
| Container `api` | Container `api` trên **EC2 có sẵn**, image kéo từ **ECR** | Chính image bạn chạy ở máy |
| Container `redis` | Container `redis` trên cùng EC2 | Đơn giản, miễn phí |

**API lấy mật khẩu thế nào (không có access key nào):** EC2 được gắn một **IAM role**. AWS tự cấp credentials ngắn hạn cho instance, nên không có access key nào trên server. Role này chỉ được đọc đúng các secret của DB, pull image và tải script SQL. Một script trên EC2 đọc secret, ghép connection string rồi khởi động container.

---

## 2. Chuẩn bị

### 2.1 Chọn region trên console 🌐

Ở **góc trên bên phải** console, bấm tên region và chọn **Asia Pacific (Singapore) ap-southeast-1**.

> Region được chọn riêng cho mỗi trang. Trước mỗi bước, nhìn lại góc trên bên phải: EC2, RDS, ECR, S3 bucket và các secret **phải cùng một region**. Tạo nhầm region là lỗi hay gặp nhất ("không tìm thấy secret", "không thấy instance").

### 2.2 AWS CLI trên PC 💻 (chỉ để push image)

Cần **AWS CLI** và **Docker Desktop** trên PC. Lần đầu, chạy `aws configure`:

```powershell
aws configure
# AWS Access Key ID:     <access key của IAM user>
# AWS Secret Access Key: <secret key>
# Default region name:   ap-southeast-1      ← gõ đúng tên này, đừng để trống
# Default output format: json
```

> **Lấy access key cho PC:** 🌐 **IAM → Users → chọn user của bạn → Security credentials → Create access key → Command Line Interface (CLI)**. Key này chỉ nằm trên PC của bạn, **không bao giờ** đưa lên EC2 hay Git.
>
> Đừng chạy nguyên văn `aws configure set region NEW_REGION`. `NEW_REGION` chỉ là chỗ để điền tên region. Nếu lỡ chạy thì chạy lại `aws configure set region ap-southeast-1`.

Kiểm tra: `aws sts get-caller-identity` phải in ra Account của bạn.

> **Chi phí:** RDS SQL Server, EC2 và địa chỉ public IPv4 đều tính tiền theo giờ khi đang chạy. Xem trạng thái Free Tier trong 🌐 **Billing and Cost Management**. Học xong thì làm theo [§12](#12-dọn-dẹp-ngừng-trả-tiền).

---

## 3. Kiểm tra EC2 có sẵn 🌐

### 3.1 Xem thông tin instance

**EC2 → Instances → tích chọn instance của bạn.** Ở bảng chi tiết phía dưới:

| Tab | Thông tin | Cần là | Nếu khác thì |
|---|---|---|---|
| Details | **Instance state** | `Running` | **Instance state → Start instance** |
| Details | **Public IPv4 address** | có giá trị → đây là `<EC2-PUBLIC-IP>` | Rỗng: **EC2 → Elastic IPs → Allocate**, rồi **Actions → Associate** vào instance |
| Details | **Instance type** | `t3.*`, `t2.*` … (x86) | Có chữ **`g`** (`t4g`, `m7g` …) là ARM: build image với `--platform linux/arm64` ở §4.2 |
| Details | **AMI name** / Platform | Amazon Linux 2023 (`al2023-…`) | Hệ điều hành khác thì lệnh cài ở §8.1 sẽ khác |
| Security | **Security groups** | tên security group → đây là `<EC2-SG>` | Thêm rule ở §5 |
| Security | **IAM Role** | `english-ec2-role` | Trống là bình thường lúc này, sẽ gắn ở §7 |
| Storage | Dung lượng **Root device** | ≥ 15 GB | Xem §3.2 |

### 3.2 Tăng ổ đĩa (nếu < 15 GB)

Image chứa công cụ SQL ở §8.3 nặng ~1.6 GB.

1. 🌐 **Tab Storage → bấm Volume ID → Actions → Modify volume → Size: 20 → Modify.**
2. 🐧 Mở rộng phân vùng trên EC2 (sau khi kết nối ở §3.3):
   ```bash
   lsblk                          # xem tên disk, ví dụ nvme0n1
   sudo growpart /dev/nvme0n1 1
   sudo xfs_growfs -d /
   df -h /                        # kiểm tra lại
   ```

### 3.3 Mở terminal của EC2 ngay trên trình duyệt

**EC2 → Instances → chọn instance → Connect → tab EC2 Instance Connect → Username: `<USER>` (ví dụ `ec2-server`) → Connect.**

Một tab mới mở ra với terminal của EC2. Mọi bước 🐧 trong hướng dẫn đều làm ở đây, không cần SSH hay file `.pem`.

> **Không kết nối được?** EC2 Instance Connect đi qua dải IP của AWS, không phải IP của bạn. Nếu port 22 chỉ mở cho "My IP", hãy thêm một rule nữa (§5.1): Type **SSH**, Source **Custom** → gõ `com.amazonaws.ap-southeast-1.ec2-instance-connect` rồi chọn prefix list hiện ra.
>
> Muốn dùng SSH từ PC: `ssh -i <KEY>.pem <USER>@<EC2-PUBLIC-IP>`.

---

## 4. ECR: nơi chứa image

### 4.1 Tạo repository 🌐

**Amazon ECR → Private registry → Repositories → Create repository**

- Repository name: **`english-api`**
- Các mục khác giữ mặc định → **Create**

### 4.2 Push image từ PC 💻

**ECR → Repositories → `english-api` → View push commands.** AWS hiện sẵn **4 lệnh đã điền đúng account và region**. Chọn tab **Windows**, rồi copy từng lệnh chạy trong PowerShell tại thư mục project:

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\WFMTTC_API\Learning_EngLish
```

| # | Lệnh trong "View push commands" | Sửa gì |
|---|---|---|
| 1 | `... aws ecr get-login-password ... docker login ...` | Giữ nguyên |
| 2 | `docker build -t english-api .` | Thêm `--platform linux/amd64` (hoặc `linux/arm64` nếu instance ARM): `docker build --platform linux/amd64 -t english-api .` |
| 3 | `docker tag english-api:latest <...>/english-api:latest` | Đổi **cả hai** `latest` thành phiên bản: `docker tag english-api:latest <...>/english-api:1.0` |
| 4 | `docker push <...>/english-api:latest` | Đổi `latest` thành `1.0` |

Kiểm tra 🌐: bấm vào repository `english-api`, phải thấy image tag **`1.0`**.

> Dùng tag phiên bản (`1.0`, `1.1` …), đừng dùng `latest`. Khi cần rollback chỉ việc chạy lại tag cũ ([§10](#10-release-phiên-bản-mới-và-rollback)).

---

## 5. Security group (tường lửa) 🌐

### 5.1 Rule cho security group của EC2 (`<EC2-SG>`)

**EC2 → Security Groups → chọn `<EC2-SG>` → tab Inbound rules → Edit inbound rules.** Đảm bảo có:

| Type | Port | Source | Lý do |
|---|---|---|---|
| SSH | 22 | **My IP** | SSH từ PC (nếu dùng). Không bao giờ để `0.0.0.0/0` |
| SSH | 22 | Prefix list `com.amazonaws.ap-southeast-1.ec2-instance-connect` | EC2 Instance Connect trên trình duyệt (§3.3) |
| HTTP | 80 | **Anywhere-IPv4** (`0.0.0.0/0`) | API public |

**Save rules.** Outbound rules: giữ mặc định (All traffic).

### 5.2 Tạo security group cho RDS: `english-rds-sg`

**EC2 → Security Groups → Create security group**

- Security group name: **`english-rds-sg`**
- Description: `SQL Server, only from the API EC2`
- VPC: **cùng VPC với EC2** (xem ở tab Networking của instance)
- Inbound rules → **Add rule**:

| Type | Port | Source |
|---|---|---|
| **MSSQL** | 1433 (tự điền) | **Custom** → gõ `sg-` rồi chọn **`<EC2-SG>`** trong danh sách |

- **Create security group**

Chọn source là một security group nghĩa là "mọi instance đang gắn `<EC2-SG>`". Chỉ EC2 của bạn vào được database, kể cả khi IP của nó đổi.

---

## 6. RDS và Secrets Manager 🌐

### 6.1 Tạo RDS

**RDS → Databases → Create database**

| Mục | Chọn | Ghi chú |
|---|---|---|
| Choose a database creation method | **Standard create** | |
| Engine type | **Microsoft SQL Server** | |
| Database management type | Amazon RDS | |
| Edition | **SQL Server Express Edition** | Rẻ nhất; giới hạn 10 GB là quá đủ |
| Engine version | Bản mới nhất có sẵn | Xem ghi chú `.bak` bên dưới |
| Templates | **Free tier** (nếu có), không thì **Dev/Test** | |
| DB instance identifier | `english-db` | |
| Master username | `admin` | Thay cho `sa` |
| Credentials management | **Managed in AWS Secrets Manager - most secure** | RDS tự sinh mật khẩu và lưu vào secret `rds!db-…` |
| Encryption key | `aws/secretsmanager` (mặc định) | |
| DB instance class | `db.t3.micro` (hoặc nhỏ nhất được liệt kê) | |
| Storage | gp3, 20 GiB; mở **Additional storage configuration** → **bỏ tích** *Enable storage autoscaling* | Tránh chi phí bất ngờ |
| Compute resource | **Don't connect to an EC2 compute resource** | Ta tự cấu hình security group ở §5 |
| Virtual private cloud (VPC) | **Cùng VPC với EC2** | |
| **Public access** | **No** | Database không có địa chỉ internet |
| VPC security group | **Choose existing** → chọn **`english-rds-sg`**, bấm **×** để bỏ `default` | |
| Additional configuration → Backup retention | 1–7 days | Backup tự động hằng ngày |
| Deletion protection | Tích chọn, nếu data quan trọng | |

**Create database.** Chờ khoảng 10–20 phút đến khi **Status = Available**, rồi bấm vào `english-db` và ghi lại:

- Tab **Connectivity & security → Endpoint**, ví dụ `english-db.abc123xyz.ap-southeast-1.rds.amazonaws.com`
- Tab **Configuration → Master credentials ARN**, ví dụ `arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:rds!db-1a2b…`

> **Về file `.bak`:** một bản backup chỉ restore được lên SQL Server **cùng hoặc mới hơn** phiên bản gốc. Database Docker của bạn là **SQL Server 2025**. Nếu RDS chỉ có bản 2022 thì file `.bak` không restore được. Vì vậy §8.3 dựng database từ `database/*.sql`, cách này chạy được trên mọi phiên bản.
>
> **Xoay vòng mật khẩu master:** RDS tự đổi mật khẩu `admin` (mặc định 7 ngày một lần). API không bị ảnh hưởng vì API dùng login riêng.

### 6.2 Tạo secret cho API

API **không** dùng `admin`. API dùng login `english_app` (chỉ đọc/ghi data), giống ở máy local.

**Bước 1: sinh mật khẩu bằng CloudShell.** Bấm biểu tượng **CloudShell** `>_` trên thanh trên cùng của console. Đây là terminal chạy ngay trong console, có sẵn AWS CLI và đã đăng nhập. Chạy:

```bash
aws secretsmanager get-random-password --password-length 24 --require-each-included-type \
  --exclude-characters "\"'\$;#\\/@\` " --query RandomPassword --output text
```

Copy chuỗi in ra. Lệnh này đã loại các ký tự `" ' $ ; # \ / @`, backtick và dấu cách, vì chúng làm hỏng connection string ([06 #2, #9](06-known-issues.md)). Nếu tự nghĩ mật khẩu, hãy tránh các ký tự này và dùng ≥ 12 ký tự có chữ hoa, chữ thường, số.

**Bước 2: tạo secret.** **Secrets Manager → Store a new secret**

1. Secret type: **Other type of secret**
2. Key/value pairs: bấm **+ Add row** để có đủ 5 dòng:

   | Key | Value |
   |---|---|
   | `host` | Endpoint RDS ở §6.1 |
   | `port` | `1433` |
   | `dbname` | `EnglishVocabularyTraining` |
   | `username` | `english_app` |
   | `password` | mật khẩu vừa sinh |

3. Encryption key: `aws/secretsmanager` → **Next**
4. Secret name: **`english-learning/prod/db`** → **Next**
5. Configure rotation: **để tắt** → **Next** → **Store**

Kiểm tra: mở secret → **Retrieve secret value** → thấy đủ 5 key.

Giờ bạn có 2 secret (**Secrets Manager → Secrets**):

| Secret | Chứa | Dùng bởi |
|---|---|---|
| `rds!db-…` (RDS tạo) | `username`, `password` của `admin` | Chỉ bước setup một lần ở §8.3 |
| `english-learning/prod/db` | Mọi thứ API cần | API, mỗi lần khởi động |

---

## 7. S3 bucket và IAM role 🌐

### 7.1 Upload script SQL lên S3

EC2 cần 3 file trong `database/`. Cách dễ nhất qua console là đưa chúng lên S3, rồi EC2 tải về.

1. **S3 → Create bucket**
   - Bucket name: **`english-learning-deploy-<ACCOUNT-ID>`** (tên bucket phải duy nhất trên toàn AWS)
   - Region: `ap-southeast-1`
   - **Block all public access**: giữ **bật**
   - **Create bucket**
2. Mở bucket → **Upload → Add folder** → chọn thư mục `C:\Mini-Project\WFMTTC\English-Learning\database` → **Upload**.
   Bucket giờ có `database/01-schema.sql`, `02-seed.sql`, `03-app-login.sql`, `init-db.sh`.

> Hoặc 💻 dùng SSH: `scp -i <KEY>.pem -r C:\Mini-Project\WFMTTC\English-Learning\database <USER>@<EC2-PUBLIC-IP>:~/` rồi bỏ qua bước tải ở §8.2.

### 7.2 Tạo IAM role

**IAM → Roles → Create role**

1. Trusted entity type: **AWS service** → Use case: **EC2** → **Next**
2. Add permissions: tìm và tích **`AmazonEC2ContainerRegistryReadOnly`** → **Next**
3. Role name: **`english-ec2-role`** → **Create role**

Thêm quyền đọc secret và S3: mở role `english-ec2-role` → **Add permissions → Create inline policy → tab JSON**, xoá nội dung có sẵn, dán đoạn sau. Thay **`123456789012`** bằng `<ACCOUNT-ID>` (3 chỗ):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadDbSecrets",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": [
        "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:english-learning/prod/db-*",
        "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:rds!db-*"
      ]
    },
    {
      "Sid": "ReadDeployBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetObject"],
      "Resource": [
        "arn:aws:s3:::english-learning-deploy-123456789012",
        "arn:aws:s3:::english-learning-deploy-123456789012/*"
      ]
    }
  ]
}
```

**Next** → Policy name: `read-english-deploy` → **Create policy**.

Role này chỉ đọc được đúng các secret và bucket trên, **không làm được gì khác**. Phần `-*` khớp với 6 ký tự ngẫu nhiên AWS thêm vào cuối ARN của secret.

> Sau bước setup ở §8.3 có thể xoá dòng `rds!db-*` (role không cần đọc mật khẩu admin nữa).

### 7.3 Gắn role vào EC2

**EC2 → Instances → chọn instance → Actions → Security → Modify IAM role → chọn `english-ec2-role` → Update IAM role.**

Không cần khởi động lại instance. Kiểm tra lại tab **Security → IAM Role** của instance.

---

## 8. Chạy API trên EC2 🐧

Mở terminal của EC2 (§3.3). Mọi lệnh trong phần này **copy và dán vào đó**.

### 8.1 Cài Docker, Compose và jq

```bash
sudo dnf install -y docker jq
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# Plugin Docker Compose (không có trong repo của Amazon Linux); $(uname -m) tự chọn x86_64 / aarch64
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

**Đóng tab terminal rồi Connect lại** (§3.3) để quyền group docker có hiệu lực. Sau đó kiểm tra:

```bash
docker compose version
aws sts get-caller-identity    # phải thấy .../english-ec2-role/...
```

Nếu báo `Unable to locate credentials`, role chưa được gắn (§7.3). Nếu báo `'compose' is not a docker command`, xem §13.

### 8.2 Tải script SQL từ S3

Thay `<ACCOUNT-ID>`:

```bash
aws s3 cp s3://english-learning-deploy-<ACCOUNT-ID>/database ~/database --recursive
ls ~/database          # 01-schema.sql  02-seed.sql  03-app-login.sql  init-db.sh
```

### 8.3 Tạo database (chỉ một lần)

Script này làm việc giống `db-init` ở máy local, nhưng trên RDS. Cả hai mật khẩu đều đọc từ Secrets Manager.

**Copy toàn bộ khối dưới đây, dán vào terminal và nhấn Enter:**

```bash
cat > ~/init-rds.sh <<'EOF'
#!/bin/bash
# Setup một lần: tạo schema, seed data và login english_app trên RDS.
set -euo pipefail

REGION="ap-southeast-1"
APP_SECRET_ID="english-learning/prod/db"
MASTER_SECRET_ARN="${1:?Cách dùng: ~/init-rds.sh '<Master credentials ARN>' [login-only]}"

get_secret() {
    aws secretsmanager get-secret-value --region "$REGION" --secret-id "$1" \
        --query SecretString --output text
}

master=$(get_secret "$MASTER_SECRET_ARN")
app=$(get_secret "$APP_SECRET_ID")

RDS_HOST=$(jq -r .host <<<"$app")
MASTER_USER=$(jq -r .username <<<"$master")
APP_DB_PASSWORD=$(jq -r .password <<<"$app")
# sqlcmd tự đọc biến SQLCMDPASSWORD, nên mật khẩu không xuất hiện trên dòng lệnh
export SQLCMDPASSWORD=$(jq -r .password <<<"$master")

# Dùng sqlcmd trong image SQL Server, giống db-init trong docker-compose.yml
sqlcmd() {
    docker run --rm -e SQLCMDPASSWORD -v ~/database:/scripts:ro \
        --entrypoint /opt/mssql-tools18/bin/sqlcmd \
        mcr.microsoft.com/mssql/server:2025-latest \
        -S "$RDS_HOST,1433" -U "$MASTER_USER" -C -b "$@"
}

echo "Đang kết nối $RDS_HOST ..."
sqlcmd -Q "SELECT @@VERSION"

if [ "${2:-}" != "login-only" ]; then
    echo "Tạo schema ..."
    sqlcmd -i /scripts/01-schema.sql
    echo "Thêm seed data ..."
    sqlcmd -i /scripts/02-seed.sql
fi

echo "Tạo/cập nhật login english_app ..."
sqlcmd -v APP_DB_PASSWORD="$APP_DB_PASSWORD" -i /scripts/03-app-login.sql

echo "Database RDS đã sẵn sàng."
EOF
chmod +x ~/init-rds.sh
```

Chạy, với **Master credentials ARN** ở §6.1 (giữ dấu nháy đơn vì ARN có ký tự `!`):

```bash
~/init-rds.sh 'arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:rds!db-xxxxxxxx'
```

Kết quả đúng: in ra phiên bản SQL Server, cuối cùng là `Database RDS đã sẵn sàng.`

> Chỉ chạy đầy đủ **một lần**. Chạy lại sẽ lỗi vì bảng đã tồn tại. Khi đổi mật khẩu trong secret, chỉ cập nhật login bằng cách thêm `login-only` vào cuối lệnh (§10).

Giải phóng ổ đĩa: `docker image rm mcr.microsoft.com/mssql/server:2025-latest`

### 8.4 File compose cho EC2

Bản rút gọn của `docker-compose.yml` ở local, chỉ còn `api` và `redis`. Connection string lấy từ script (§8.5), nên không bao giờ nằm trong file. Copy, dán, Enter:

```bash
mkdir -p ~/app
cat > ~/app/docker-compose.yml <<'EOF'
name: english-learning

services:
  api:
    image: ${API_IMAGE}
    container_name: english-api
    restart: unless-stopped               # tự chạy lại khi crash hoặc reboot
    ports:
      - "80:8080"                         # port public 80 → port 8080 của API
    environment:
      # Không đặt ASPNETCORE_ENVIRONMENT = Production (không có Swagger)
      ConnectionStrings__DefaultConnection: "${DB_CONNECTION_STRING}"
      Redis__ConnectionString: "redis:6379"
    depends_on:
      redis:
        condition: service_healthy

  redis:
    image: redis:alpine
    container_name: redis
    restart: unless-stopped
    # không có "ports:": chỉ container api vào được Redis (Redis không có mật khẩu)
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
```

### 8.5 Script khởi động

Copy, dán, Enter:

```bash
cat > ~/app/start-api.sh <<'EOF'
#!/bin/bash
# Cách dùng: ~/app/start-api.sh 1.0 → đọc secret DB, pull english-api:1.0 từ ECR, (khởi động lại) container.
set -euo pipefail

TAG="${1:?Cách dùng: ~/app/start-api.sh <image tag>, ví dụ ~/app/start-api.sh 1.0}"
REGION="ap-southeast-1"
SECRET_ID="english-learning/prod/db"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# 1. Đọc secret và ghép connection string
secret=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ID" \
    --query SecretString --output text)
host=$(jq -r .host <<<"$secret")
port=$(jq -r .port <<<"$secret")
db=$(jq -r .dbname <<<"$secret")
user=$(jq -r .username <<<"$secret")
pass=$(jq -r .password <<<"$secret")

# Encrypt=True: dữ liệu tới RDS được mã hoá.
# TrustServerCertificate=True: bỏ qua bước kiểm tra chứng chỉ của RDS (chấp nhận được trong VPC riêng).
export DB_CONNECTION_STRING="Server=$host,$port;Database=$db;User Id=$user;Password=$pass;Encrypt=True;TrustServerCertificate=True;"
export API_IMAGE="$REGISTRY/english-api:$TAG"

# 2. Pull image (login ECR chỉ có hiệu lực 12 giờ, nên lần nào cũng login lại)
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

# 3. Khởi động, hoặc thay container đang chạy
cd "$(dirname "$0")"
docker compose pull
docker compose up -d

echo "Đã chạy $API_IMAGE. Kiểm tra: curl http://localhost/health"
EOF
chmod +x ~/app/start-api.sh
```

### 8.6 Chạy và kiểm tra

```bash
~/app/start-api.sh 1.0
docker compose -f ~/app/docker-compose.yml ps
curl http://localhost/health            # → Healthy
```

🌐 Mở trên trình duyệt: `http://<EC2-PUBLIC-IP>/health` → **Healthy**, và `http://<EC2-PUBLIC-IP>/api/...` trả về data từ RDS.

`Healthy` nghĩa là API đã đăng nhập RDS bằng `english_app` với mật khẩu lấy từ Secrets Manager. Mọi thứ đã kết nối xong.

Xem log: `docker logs -f english-api` (Ctrl + C để thoát).

---

## 9. Cách B: API tự đọc Secrets Manager

Ở §8, script đặt mật khẩu vào biến môi trường. Ai chạy được `docker inspect english-api` trên server đều thấy mật khẩu. Nếu điều đó quan trọng, hãy để API tự lấy secret khi khởi động. Khi đó container chỉ nhận **tên** secret.

### 9.1 Sửa code 💻

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\WFMTTC_API\Learning_EngLish
dotnet add package AWSSDK.SecretsManager
```

Trong `Program.cs`, ngay sau `var builder = WebApplication.CreateBuilder(args);`:

```csharp
// Trên AWS: ghép connection string từ Secrets Manager.
// Ở local không đặt Aws:DbSecretId nên đoạn này bị bỏ qua; appsettings / user secrets / .env vẫn dùng như cũ.
var dbSecretId = builder.Configuration["Aws:DbSecretId"];
if (!string.IsNullOrWhiteSpace(dbSecretId))
{
    using var secretsClient = new AmazonSecretsManagerClient();   // credentials lấy từ role của EC2
    var secret = await secretsClient.GetSecretValueAsync(new GetSecretValueRequest { SecretId = dbSecretId });

    // Web defaults: tên thuộc tính không phân biệt hoa thường, và chấp nhận "port": "1433" (dạng chuỗi)
    var db = JsonSerializer.Deserialize<DbSecret>(secret.SecretString, new JsonSerializerOptions(JsonSerializerDefaults.Web))
             ?? throw new InvalidOperationException($"Secret '{dbSecretId}' rỗng.");

    builder.Configuration["ConnectionStrings:DefaultConnection"] = new SqlConnectionStringBuilder
    {
        DataSource = $"{db.Host},{db.Port}",
        InitialCatalog = db.DbName,
        UserID = db.Username,
        Password = db.Password,
        TrustServerCertificate = true,   // Encrypt đã bật sẵn theo mặc định
    }.ConnectionString;
}
```

Thêm using ở đầu file:

```csharp
using System.Text.Json;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Microsoft.Data.SqlClient;
```

Và ở **cuối cùng** của `Program.cs` (C# yêu cầu khai báo kiểu đặt sau code top-level):

```csharp
record DbSecret(string Host, int Port, string DbName, string Username, string Password);
```

Không cần sửa gì khác, vì `SqlConnectionFactory` và `DatabaseHealthCheck` đọc connection string lúc được tạo, tức là sau khi đoạn code trên đã chạy.

### 9.2 Thay đổi khi deploy

🐧 Trong `~/app/docker-compose.yml` (`nano ~/app/docker-compose.yml`), thay dòng `ConnectionStrings__DefaultConnection` bằng:

```yaml
      Aws__DbSecretId: "english-learning/prod/db"
      AWS_REGION: "ap-southeast-1"
```

🐧 Trong `start-api.sh`, xoá bước 1 (đọc secret và ghép connection string). Giữ lại `TAG`, `REGION`, `ACCOUNT`, `REGISTRY`, `API_IMAGE` và bước 2–3.

🌐 **Thêm một thiết lập cho EC2:** container nằm xa server thêm một "hop" mạng. Mặc định credentials của instance chỉ tới được 1 hop, nên SDK chạy trong container không lấy được. Nâng giới hạn lên 2:

**EC2 → Instances → chọn instance → Actions → Instance settings → Modify instance metadata options**

- Instance metadata service: **Enable**
- IMDSv2: **Required**
- Metadata response hop limit: **2**
- **Save**

Thiếu bước này, API lỗi ngay khi khởi động với `Unable to get IAM security credentials from EC2 Instance Metadata Service`.

Build lại, push tag mới (§10), rồi kiểm tra lại `/health`.

| | Cách A (script, §8) | Cách B (trong app, §9) |
|---|---|---|
| Sửa code | Không | ~25 dòng + 1 package |
| Mật khẩu thấy được qua `docker inspect` | Có | Không, chỉ thấy tên secret |
| Thiết lập thêm cho EC2 | Không | Hop limit = 2 |

---

## 10. Release phiên bản mới và rollback

**Release:**
1. 💻 Làm lại §4.2 (**View push commands**), đổi tag thành **`1.1`**.
2. 🐧 `~/app/start-api.sh 1.1` rồi `curl http://localhost/health`.

**Rollback:** 🐧 `~/app/start-api.sh 1.0`. Image cũ vẫn còn trên ECR.

**Đổi mật khẩu của `english_app`:**
1. 🌐 **Secrets Manager → `english-learning/prod/db` → Retrieve secret value → Edit** → sửa `password` → **Save**.
2. 🐧 Áp mật khẩu mới cho login trên RDS (cần quyền `rds!db-*` trong role):
   ```bash
   ~/init-rds.sh '<Master credentials ARN>' login-only
   ```
3. 🐧 Khởi động lại API để đọc giá trị mới: `~/app/start-api.sh <tag đang chạy>`.

API **chỉ đọc secret lúc khởi động**.

---

## 11. Bước tiếp theo

| Chủ đề | Việc cần làm |
|---|---|
| **Frontend** | Push `english-frontend` lên ECR và chạy trên cùng EC2, hoặc host trên S3 + CloudFront. Đặt `API_BASE_URL` thành `http://<EC2-PUBLIC-IP>/api` và **thêm URL frontend vào CORS** trong `Program.cs` ([03 §10.3](03-docker.md#103-things-to-change-before-a-real-deployment)) |
| **HTTPS + địa chỉ cố định** | 🌐 **EC2 → Load Balancers → Create Application Load Balancer** với chứng chỉ từ **Certificate Manager**, hoặc ít nhất gắn **Elastic IP** để địa chỉ không đổi khi stop instance |
| **Chuyển data thật** | Nếu RDS cùng hoặc mới hơn phiên bản SQL Server ở máy: 🌐 **RDS → Option groups** tạo option group có `SQLSERVER_BACKUP_RESTORE`, gắn vào DB, upload `.bak` lên S3, rồi chạy `exec msdb.dbo.rds_restore_database`. Nếu không, xuất data thành script (DBeaver / SSMS "Generate Scripts" kèm data), upload lên S3 và chạy bằng `sqlcmd` như §8.3 |
| **Bỏ hẳn SSH** | Gắn thêm `AmazonSSMManagedInstanceCore` vào role và dùng 🌐 **Connect → Session Manager**, rồi xoá rule port 22 |
| **Cảnh báo** | 🌐 **CloudWatch → Alarms → Create alarm** cho status check của EC2, CPU và *FreeStorageSpace* của RDS |

---

## 12. Dọn dẹp (ngừng trả tiền) 🌐

| Tài nguyên | Tạm dừng | Xoá hẳn |
|---|---|---|
| EC2 | **Instance state → Stop instance** (vẫn trả tiền ổ đĩa) | **Terminate instance** (mất mọi thứ trên instance) |
| Container trên EC2 (giữ instance) | 🐧 `docker compose -f ~/app/docker-compose.yml down` | Thêm `docker image prune -a` |
| RDS | **Actions → Stop temporarily** (sau **7 ngày** AWS tự bật lại) | **Modify** → bỏ Deletion protection → **Actions → Delete** (chụp final snapshot nếu muốn giữ data) |
| Secrets | ~$0.40 / secret / tháng | **Actions → Delete secret** (chờ 7–30 ngày). Secret `rds!db-…` bị xoá cùng database |
| S3 bucket | Gần như miễn phí | **Empty** rồi **Delete** |
| Image trên ECR | Vài cent mỗi GB | Chọn tag cũ → **Delete** |
| Elastic IP (nếu có) | Tính tiền khi còn tồn tại | **Disassociate** → **Release** |

---

## 13. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| Không thấy instance / secret / DB trên console | Đang xem nhầm region | Chọn **Asia Pacific (Singapore)** ở góc trên bên phải (§2.1) |
| `Provided region_name 'NEW_REGION' doesn't match a supported format` | Đã chạy nguyên văn lệnh mẫu có `NEW_REGION` | 💻 `aws configure set region ap-southeast-1` |
| `argument --region: expected one argument` | Lệnh dùng biến `$REGION` nhưng biến rỗng | Dùng lệnh từ **View push commands** (§4.2), đã điền sẵn region |
| EC2 Instance Connect báo lỗi kết nối | Port 22 chưa mở cho dải IP của Instance Connect | Thêm rule SSH với prefix list `com.amazonaws.ap-southeast-1.ec2-instance-connect` (§5.1) |
| `sudo: apt-get: command not found` | Amazon Linux dùng `dnf` | Dùng các lệnh ở §8.1 |
| `docker: 'compose' is not a docker command` | Bước `curl` ở §8.1 lỗi (mạng, `404`) hoặc file đặt sai chỗ | 🐧 `ls -l /usr/local/lib/docker/cli-plugins/`, chạy lại bước `curl` và đọc lỗi. File có rồi mà vẫn lỗi: copy vào `~/.docker/cli-plugins/` và `chmod +x` |
| `permission denied ... docker.sock` | Chưa kết nối lại sau `usermod -aG docker` | Đóng tab terminal, Connect lại |
| `Unable to locate credentials` | Instance chưa gắn role | §7.3 |
| `AccessDeniedException ... GetSecretValue` / `AccessDenied` khi `s3 cp` | ARN hoặc tên bucket trong policy sai | 🌐 IAM → Roles → `english-ec2-role` → sửa policy: kiểm tra account ID, region, tên bucket, hậu tố `-*` |
| `curl /health` → `Unhealthy` | API không kết nối hoặc không đăng nhập được RDS | `docker logs english-api`, rồi xem các dòng bên dưới |
| Log: `A network-related ... error` / timeout | Port 1433 bị chặn | `english-rds-sg` phải cho phép 1433 từ `<EC2-SG>`; RDS phải cùng VPC với EC2 |
| Log: `Login failed for user 'english_app'` | Mật khẩu trong secret ≠ mật khẩu trên RDS | `~/init-rds.sh '<ARN>' login-only` (§10) |
| Log: `Cannot open database "EnglishVocabularyTraining"` | Chưa chạy §8.3, hoặc đã chạy nhưng lỗi | Chạy `~/init-rds.sh '<ARN>'` và đọc output |
| `no basic auth credentials` khi pull | Chưa login ECR hoặc login đã hết hạn | Chạy lại `start-api.sh` (script lần nào cũng login), đừng gọi thẳng `docker compose up` |
| Container thoát với `exec format error` | Image build sai kiến trúc so với EC2 | Build lại với `--platform` khớp Instance type (§3.1) |
| Trình duyệt không mở được `http://<EC2-PUBLIC-IP>/health`, nhưng `curl` trên EC2 thì được | Port 80 chưa mở | Thêm HTTP 80 vào `<EC2-SG>` (§5.1). Dùng `http://`, không phải `https://` |
| Cách B: `Unable to get IAM security credentials from EC2 Instance Metadata Service` | Hop limit đang là 1 | §9.2 |
| `RedisConnectionException` | Redis chưa healthy | `docker compose -f ~/app/docker-compose.yml ps` |
| Public IP đổi sau khi Stop/Start | Bình thường với IP tự cấp | Gắn Elastic IP (§3.1) |
