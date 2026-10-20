#!/usr/bin/env node
// The CDK "app": the entry point. It creates one or more stacks.
// `cdk synth` runs this file and writes CloudFormation templates into cdk.out/.
import * as cdk from "aws-cdk-lib";
import { CloudPoseStack } from "../lib/cloudpose-stack";

const app = new cdk.App();

new CloudPoseStack(app, "CloudPoseCdk", {
  // Sydney, same as everything else. The account comes from your CLI login when you deploy.
  env: { region: "ap-southeast-2", account: process.env.CDK_DEFAULT_ACCOUNT },
  envs: ["dev", "prod"],
});

// Tags on every resource in the app (like default_tags in Terraform).
cdk.Tags.of(app).add("Project", "cloudpose");
cdk.Tags.of(app).add("ManagedBy", "cdk");
cdk.Tags.of(app).add("Owner", "anbu");
