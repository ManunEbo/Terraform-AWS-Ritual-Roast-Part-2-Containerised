# 1. Create the K8s Private Subnets
# Creating the database subnets
# For the subnets only, we're ditching the ${var.environment} to be consistent with the v1 subnets
resource "aws_subnet" "rr_k8s_private_subnets" {
    count             = length(var.k8s_subnet_list)
    vpc_id            = var.vpc_id
    cidr_block        = var.k8s_subnet_list[count.index].cidr
    availability_zone = var.k8s_subnet_list[count.index].az

    # The kubernetes.io/role/internal-elb tag is a strict K8s requirement.
    # It allows the AWS Cloud Controller to automatically find these subnets 
    # when you create internal LoadBalancers in Kubernetes later.
    tags = merge(var.common_tags, {
        Name = var.k8s_subnet_list[count.index].subnet_name
        "kubernetes.io/role/internal-elb" = "1"
    })
}