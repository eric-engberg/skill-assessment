# skill-assessment
This project is a skill assessment that I did for a job interview.
The required steps were to create a server within AWS, run a mysql
container which is accessed by the hostname 'mysql' and a container
that would run a small django app.

Everything is configured and deployed using terraform with 0.12
syntax.  A single `terraform apply` will bring up all resources.
The django app can be acessed from port 8000 on the public IP of 
the EC2 instance that is created.

I made two adjustments to the django app.
   1. Updated django from 3.0.2 to 3.0.3 to resolve a CVE
   2. Added '*' to ALLOWED_HOSTS so that the app could be accessed remotely.

Running terraform apply will do the following:
  1. Create an ssh key for accessing the EC2 instance for debugging purposes
  2. Write out both the private and public keys to disk.
  3. Create a VPC to use
  4. Create both an Internet gateway and a NAT gateway
  5. Assign an elastic IP to the nat gateway
  6. Create 2 subnets within the VPC
     1. Subnet for the EC2 instance that routes via the IGW
     2. Subnet for the mysql container that routes via the NAT gateway. (No public IPs)
  7. Create security groups for the EC2 instance and the mysql container.
  8. Assign rules to the previously created security groups
  9. Create an ECR repository for the django container
  10. Build the django container
  11. Tags the django container
  12. Pushes the built container to the ECR repository
  13. Creates a service discovery for the mysql instance.
  14. Create various IAM roles for the ECS instance
  15. Create an ASG launch configuration
      1.  Use a script run via user_data to configure which ECS cluster to serve
  16. Create the auto scaling group (min/max/desired = 1)
  17. Creates an ECS cluster that the ASG EC2 instance will serve
  18. Create a task and service for the mysql container
  19. Create a task and service for the django app container