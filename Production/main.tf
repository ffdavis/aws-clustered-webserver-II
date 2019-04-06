# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE ALL THESE RESOURCES TO DEPLOY AN APP IN AN AUTO SCALING GROUP WITH AN ELB
#
#  - aws_autoscaling_group.example
#  - aws_elb.example
#  - aws_launch_configuration.example
#  - aws_security_group.elb
#  - aws_security_group.instance
#
# This template runs a simple "Hello, World" web server in Auto Scaling Group (ASG) with an Elastic Load Balancer
# (ELB) in front of it to distribute traffic across the EC2 Instances in the ASG.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ------------------------------------------------------------------------------
# 1- Configure our AWS CONNECTION
# ------------------------------------------------------------------------------

# provider "aws" {
#   region = "us-east-1"
# }

provider "aws" {
  shared_credentials_file = "~/.aws/credentials"
  region = "${var.region}"
  profile = "default"
}

# ---------------------------------------------------------------------------------------------------------------------
# 2 - GET THE LIST OF AVAILABILITY ZONES IN THE CURRENT REGION
# Every AWS accout has slightly different availability zones in each region. For example, one account might have
# us-east-1a, us-east-1b, and us-east-1c, while another will have us-east-1a, us-east-1b, and us-east-1d. This resource
# queries AWS to fetch the list for the current account and region.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_availability_zones" "all" {}

# ---------------------------------------------------------------------------------------------------------------------
# 3 - Create the SECURITY GROUP that's applied to each EC2 instance in the ASG
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  # Inbound HTTP from anywhere
  ingress {
    from_port = "${var.server_port}"
    to_port = "${var.server_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 4- Create a LAUNCH CONFIGURATION that defines each EC2 instance in the ASG
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_launch_configuration" "example" {

  # Ubuntu Server 14.04 LTS (HVM), SSD Volume Type in us-east-1
  # image_id = "ami-2d39803a"

  # Ubuntu Server 18.04 LTS (HVM), SSD Volume Type - ami-0a313d6098716f372 (64-bit x86)
  image_id = "ami-0a313d6098716f372"
  
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.instance.id}"]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p "${var.server_port}" &
              EOF

  # Important note: whenever using a launch configuration with an auto scaling group, you must set
  # create_before_destroy = true. However, as soon as you set create_before_destroy = true in one resource, you must
  # also set it in every resource that it depends on, or you'll get an error about cyclic dependencies (especially when
  # removing resources). For more info, see:
  #
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  # https://terraform.io/docs/configuration/resources.html
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 5 - Create a SECURITY GROUP that controls what traffic goes in and goes out of the ELB
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "elb" {
  name = "terraform-example-elb"

  # Allow all outbound
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound HTTP from anywhere
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 6- Create an ELB to route traffic across the AUTO SCALING GROUP (ASG)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_elb" "example" {
  name = "terraform-asg-example"
  security_groups = ["${aws_security_group.elb.id}"]
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:${var.server_port}/"
  }

  # This adds a listener for incoming HTTP requests.
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "${var.server_port}"
    instance_protocol = "http"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 7 - Create the AUTO SCALING GROUP (ASG)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_autoscaling_group" "example" {
  launch_configuration = "${aws_launch_configuration.example.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  min_size = 2
  max_size = 10

  load_balancers = ["${aws_elb.example.name}"]
  health_check_type = "ELB"

  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 8 - RUN
# ---------------------------------------------------------------------------------------------------------------------
# Get the <elb_dns_name> from the output of TERRAFORM APPLY
# curl http://<elb_dns_name>
# curl http://terraform-asg-example-1861524558.us-east-1.elb.amazonaws.com


# ---------------------------------------------------------------------------------------------------------------------
# 8 - NOTES
# ---------------------------------------------------------------------------------------------------------------------
# Of course, there are many other aspects to an ASG that we have not covered here. For a real deployment, you would need 
# to attach IAM roles to the EC2 Instances, set up a mechanism to update the EC2 Instances in the ASG with zero-downtime,
# and configure auto scaling policies to adjust the size of the ASG in response to load. For a fully pre-assembled, 
# battle-tested, documented, production-ready version of the ASG, as well as other types of infrastructure such as 
# Docker clusters, relational databases, VPCs, and more, you may want to check out the Gruntwork Infrastructure Packages.

