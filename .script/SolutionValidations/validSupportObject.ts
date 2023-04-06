import { MainTemplateSupportObjectValidationError } from "./../utils/validationError";
import { ExitCode } from "../utils/exitCode";
import fs from "fs";

// function to check if the solution has a valid support object
export function IsValidSupportObject(filePath: string): ExitCode {

    // check if the file is a mainTemplate.json file
    if (filePath.endsWith("mainTemplate.json")) {
        // read the content of the file
        let jsonFile = JSON.parse(fs.readFileSync(filePath, "utf8"));

        // check if the file has a "resources" field
        if (!jsonFile.hasOwnProperty("resources")) {
            console.warn(`No "resources" field found in the file. Skipping file path: ${filePath}`);
            return ExitCode.SUCCESS;
        }

        // get the resources from the file
        let resources = jsonFile.resources;

        // filter resources that have type "Microsoft.OperationalInsights/workspaces/providers/metadata"
        const filteredResource = resources.filter(function (resource: { type: string; }) {
            return resource.type === "Microsoft.OperationalInsights/workspaces/providers/metadata";
        });

        if (filteredResource.length > 0) {
            filteredResource.forEach((element: { hasOwnProperty: (arg0: string) => boolean; properties: { hasOwnProperty: (arg0: string) => boolean; support: { hasOwnProperty: (arg0: string) => boolean; name: any; email: any; link: any; }; }; }) => {
                // check if the resource has a "properties" field
                if (element.hasOwnProperty("properties") === true) {
                    // check if the "properties" field has a "support" field
                    if (element.properties.hasOwnProperty("support") === true) {
                        const support = element.properties.support;

                        // check if the support object has the required fields
                        if (support.hasOwnProperty("name") && (support.hasOwnProperty("email") || support.hasOwnProperty("link"))) {
                            // check if the email is valid
                            if (support.hasOwnProperty("email") && support.email.trim() !== "") {
                                const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
                                if (!emailRegex.test(support.email)) {
                                    throw new MainTemplateSupportObjectValidationError(`Invalid email format for support email: ${support.email}`);
                                }
                            }

                            // check if the link is a valid url
                            if (support.hasOwnProperty("link") && support.link.trim() !== "") {
                                const linkRegex = /^https?:\/\/\S+$/;
                                if (!linkRegex.test(support.link)) {
                                    throw new MainTemplateSupportObjectValidationError(`Invalid url format for support link: ${support.link}`);
                                }
                            }
                        } else {
                            throw new MainTemplateSupportObjectValidationError(`The support object must have "name" field and either "email" or "link" field.`);
                        }
                    } else {
                        throw new MainTemplateSupportObjectValidationError(`The "properties" field must have "support" field.`);
                    }
                }
            });
        }

        // If the file is not identified as a main template, log a warning message
    } else {
        console.warn(`Could not identify json file as a Main Template. Skipping File path: ${filePath}`);
    }

    // Return success code after completion of the check
    return ExitCode.SUCCESS;
}