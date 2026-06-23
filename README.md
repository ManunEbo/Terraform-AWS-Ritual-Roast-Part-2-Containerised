# Ritual Roast: Automated 3-Tier AWS Architecture

# 1. 🏞️ Background

Ritual Roast is a fictitious company embarking on an advertising campaign to engage with their customers by hosting a recipe competition where customers complete the online form with their recipe and contact details. The chefs will try the recipe and decide the winner to receive a prize. The company aims to build a mailing list from the emails for future campaigns.

# 2. 💡 Project Evolution & Motivation

This is the second of a three-part series of projects based on Ritual Roast. The projects are based on the architectural concepts from the [AWS Solutions Architect SAA-C03 – Hands-On Projects](https://www.udemy.com/course/aws-solutions-architect-capstone-projects/) course on Udemy. The original course consists of manual infrastructure deployments via the AWS Management Console. These projects convert that into a sophisticated Infrastructure as Code (IaC) deployment using **Terraform**. In implementing this project, I demonstrate my skills and ability to turn complex architectures into practical, production-worthy solutions.

This document is intended to be both technical and educational to bridge the gap for those new to IaC.

## a. Modular decoupled Layer approach

The project houses a poly repo decoupled into layers, five separate deployments housed in one repo. Each layer adds resources that serve a particular function. Those resources are then referenced in other layers via data sources which reach back to preceding layers for resource IDs. This makes the project flexible to infrastructure changes that would otherwise be difficult to achieve under a monolithic repo where components such as VPC, Databases and applications are all under a single deployment. In such cases switching to alternatives most likely involves destroying the entire deployment and starting a new.