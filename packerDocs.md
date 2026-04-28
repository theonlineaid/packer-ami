# Packer HCL Configuration — Full Documentation

## What is This File?

This is a **HashiCorp Packer** configuration file written in HCL (HashiCorp Configuration Language). Its job is to **automatically build a custom Amazon Machine Image (AMI)** on AWS — a pre-configured server snapshot that you can use to launch EC2 instances.

Think of it like a recipe: Packer spins up a temporary AWS server, installs your software on it, takes a snapshot (AMI), and then destroys the temporary server. You are left with a reusable image.

---

## Block-by-Block Breakdown

### 1. `packer {}` — Plugin Requirements

```hcl
packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}
```

**What it does:**  
Declares that this configuration requires the official **Packer Amazon plugin** (version 1.0.0 or newer). This plugin gives Packer the ability to talk to AWS and build AMIs.

**How to use it:**  
Before running the build, initialize the plugin by running:

```bash
packer init .
```

This downloads the plugin automatically from GitHub.

---

### 2. `variable "region"` — Input Variable

```hcl
variable "region" {
  default = "ap-southeast-2"
}
```

**What it does:**  
Defines a variable called `region` with a default value of `ap-southeast-2` (Sydney, Australia). This makes the region configurable — you can override it without editing the file.

**How to use it:**  
To use the default, do nothing. To override it at build time:

```bash
packer build -var "region=us-east-1" .
```

Or use a `.pkrvars.hcl` file:

```hcl
# myvars.pkrvars.hcl
region = "eu-west-1"
```

```bash
packer build -var-file="myvars.pkrvars.hcl" .
```

---

### 3. `source "amazon-ebs" "ubuntu"` — The Image Source

```hcl
source "amazon-ebs" "ubuntu" {
  region        = var.region
  instance_type = "t3.micro"
  source_ami    = "ami-0c33c6bd24cee108b"
  ssh_username  = "ubuntu"
  ami_name      = "my-custom-nginx-{{timestamp}}"
}
```

**What it does:**  
Defines the **base configuration** for the temporary EC2 instance Packer will launch. This is the "starting point" image.

| Field | Value | Meaning |
|---|---|---|
| `region` | `var.region` | Uses the variable defined above (ap-southeast-2) |
| `instance_type` | `t3.micro` | A small, cheap AWS instance (free tier eligible) |
| `source_ami` | `ami-0c33c6bd24cee108b` | The base Ubuntu AMI to start from (in ap-southeast-2) |
| `ssh_username` | `ubuntu` | Username Packer uses to SSH into the instance |
| `ami_name` | `my-custom-nginx-{{timestamp}}` | Name of the final AMI — timestamp makes it unique |

> **Important:** The `source_ami` is region-specific. If you change the region variable, you must also update this AMI ID to match the correct one for that region. Find the right AMI ID in the AWS Console under EC2 → AMIs → Public Images, filtering for Ubuntu.

---

### 4. `build {}` — The Build Instructions

```hcl
build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y nginx",
      "echo 'Hello from Packer AMI' | sudo tee /var/www/html/index.html"
    ]
  }
}
```

**What it does:**  
This is where Packer **actually does the work**. It references the source defined above and runs shell commands inside the temporary EC2 instance.

**The three shell commands:**

| Command | What it does |
|---|---|
| `sudo apt-get update -y` | Refreshes the list of available packages from Ubuntu's repositories |
| `sudo apt-get install -y nginx` | Installs the Nginx web server |
| `echo '...' \| sudo tee /var/www/html/index.html` | Replaces the default Nginx homepage with "Hello from Packer AMI" |

After these commands run successfully, Packer stops the instance and creates the AMI snapshot.

---

## How to Run This Configuration

### Prerequisites

1. **Install Packer** — Download from [https://developer.hashicorp.com/packer/install](https://developer.hashicorp.com/packer/install)
2. **AWS credentials configured** — Either via environment variables or AWS CLI:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-southeast-2"
```

Or using the AWS CLI:

```bash
aws configure
```

3. **IAM Permissions** — Your AWS user/role needs these permissions:
   - `ec2:DescribeImages`
   - `ec2:RunInstances`
   - `ec2:CreateImage`
   - `ec2:TerminateInstances`
   - `ec2:CreateTags`
   - `ec2:DescribeInstances`

---

### Step-by-Step Commands

**Step 1: Initialize plugins**
```bash
packer init .
```

**Step 2: Validate the configuration (check for errors)**
```bash
packer validate .
```

**Step 3: Build the AMI**
```bash
packer build .
```

**Step 4 (optional): Build with a different region**
```bash
packer build -var "region=us-east-1" .
```

---

## What Happens During the Build

When you run `packer build .`, here is what occurs step by step:

1. Packer authenticates with AWS using your credentials
2. Packer launches a temporary `t3.micro` EC2 instance from the base Ubuntu AMI
3. Packer waits for the instance to boot and SSH to become available
4. Packer SSHes into the instance using the `ubuntu` user
5. The three shell commands are executed in order (update → install nginx → write HTML)
6. Packer stops the instance
7. Packer creates an AMI snapshot named `my-custom-nginx-<timestamp>`
8. Packer **terminates** the temporary instance (you are not charged after this)
9. Packer outputs the new AMI ID (e.g., `ami-0abc1234def56789`)

---

## Output

After a successful build, you will see output like:

```
==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs.ubuntu: AMIs were created:
ap-southeast-2: ami-0abc1234def56789
```

You can now use this AMI ID to launch pre-configured EC2 instances with Nginx already installed and running.

---

## Common Issues & Tips

| Issue | Solution |
|---|---|
| `InvalidAMIID.NotFound` | The `source_ami` doesn't exist in the chosen region. Update it for your target region. |
| `AuthFailure` | AWS credentials are missing or wrong. Run `aws configure` or export env vars. |
| `timeout waiting for SSH` | Security group may be blocking port 22. Packer creates a temporary security group but VPC settings can interfere. |
| AMI name already exists | The `{{timestamp}}` in the name prevents this, but if you see it, delete the old AMI or change the name pattern. |

---

## Summary

This Packer file does one thing: **builds a custom Ubuntu AMI on AWS with Nginx pre-installed**. It is a foundation you can extend — replace the shell commands with anything you need (install Node.js, configure databases, copy application code, etc.) and Packer will bake it all into a ready-to-launch AMI.