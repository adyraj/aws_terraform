provider "aws" {
    region     = "ap-south-1"
    profile    = "myadi"
}

// Creating Key Pair

resource "tls_private_key" "web_key" {
    algorithm = "RSA"
}

resource "aws_key_pair" "task_key" {
    key_name   = "mytaskkey"
    public_key = tls_private_key.web_key.public_key_openssh
}

resource "local_file" "key-file" {
    content  = tls_private_key.web_key.private_key_pem
    filename = "task_key.pem"
}


// Creating Security Group

resource "aws_security_group" "task-security" {
    name        = "task-security-group"
    description = "Allow SSH inbound HTTP"

    ingress {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
      description = "HTTP"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }

    tags = {
      Name = "firewall-ssh-http"
  }
}

// Launch EC2 Instance

resource "aws_instance" "web" {
    ami           = "ami-0447a12f28fddb066"
    instance_type = "t2.micro"
    key_name      = aws_key_pair.task_key.key_name
    security_groups = [ aws_security_group.task-security.name ]

    tags = {
      Name = "webos"
  }

    connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.web.public_ip
        port    = 22
        private_key = tls_private_key.web_key.private_key_pem
    }
    provisioner "remote-exec" {
        inline = [
        "sudo yum install httpd -y",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
        "sudo yum install git -y"
        ]
    }
}

// Create EBS Volume

resource "aws_ebs_volume" "ebs1" {
    availability_zone = aws_instance.web.availability_zone
    size              = 1

    tags = {
      Name = "webebs"
  }
}

// Attaching EBS Volume 

resource "aws_volume_attachment" "ebs_att" {
    device_name = "/dev/sdh"
    volume_id   = aws_ebs_volume.ebs1.id
    instance_id = aws_instance.web.id
    force_detach = true

    connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.web.public_ip
        port    = 22
        private_key = tls_private_key.web_key.private_key_pem
    }

    provisioner "remote-exec" {
        inline  = [
            "sudo mkfs.ext4 /dev/xvdb",
            "sudo mount /dev/xvdb /var/www/html",
            "sudo git clone https://github.com/adyraj/task.git /var/www/html/",
        ]
    }
}

//Creating S3 Bucket

resource "aws_s3_bucket" "b" {
    bucket = "task-bucket123"
    acl    = "public-read"

    provisioner "local-exec" {
        when        =   destroy
        command     =   "echo rmdir /Q /S image"
    }


    provisioner "local-exec" {
        command     = "git clone https://github.com/adyraj/task_image.git image"
    }

    tags = {
      Name        = "My bucket"
  }
}

resource "aws_s3_bucket_object" "image_upload" {
    bucket  = aws_s3_bucket.b.bucket
    key     = "myimage.jfif"
    source  = "image/image.jfif"
    acl     = "public-read"
}

// Create Cloudfront

locals {
    s3_origin_id = "myS3_123"
    image_url = "${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image_upload.key}"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
    origin {
        domain_name = aws_s3_bucket.b.bucket_domain_name
        origin_id   = local.s3_origin_id
    }

    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }

    enabled             = true

    restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }
    viewer_certificate {
        cloudfront_default_certificate = true
    }

    connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.web.public_ip
        port    = 22
        private_key = tls_private_key.web_key.private_key_pem
    }
    provisioner "remote-exec" {
        inline  = [
            # "sudo su << \"EOF\" \n echo \"<img src='${self.domain_name}'>\" >> /var/www/html/index.html \n \"EOF\""
            "sudo su << EOF",
            "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.image_upload.key}' width=400 height=300>\" >> /var/www/html/index.html",
            "EOF"
        ]
    }
}

output "myos_ip" {
  value = aws_instance.web.public_ip
}

resource "null_resource" "nulllocal"  {
depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.web.public_ip}"
  	}
}
