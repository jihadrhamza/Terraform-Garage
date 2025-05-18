provider "aws" {
    region = "us-east-1"
    access_key=var.aws_access_key
    secret_key=var.aws_secret_key
    token=var.aws_session_token
}
resource "aws_instance" "myec2" {
    ami = "ami-0f88e80871fd81e91"
    instance_type = "t2.micro"
    tags = {
      Name = "MyFirst"
    }
}