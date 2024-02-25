# HCL Communities Cloner
This PowerShell script leverages the XML API to clone HCL Connections community folders onto local filesystem. It's designed to replicate the folder structure of specified communities, preserving the last modified dates for both folders and files.
 **It only clones the first 500 files per folder, 500 folders per community and 500 communitys** (It works recursive, so it will clone folders within folders within folders, ...)

## Setup Instructions
To prepare for using this script, please follow these steps:
1. **Configure Server URL**: Assign your server's URL to the `baseServer` and `cookieDomain` variable at the top of the `.ps1` file. (example: `https://my.company`)
2. **Authentication Token**: Obtain your `LtpaToken2` cookie from your web browser. This token is necessary for authentication.
3. **Specify Communities**: List the names of the communities you wish to clone in the `communitys.txt` file. Use "ALL" to clone all available communities.

## Usage
Execute the script with optional parameters for `Route` and `Delay`:

- `Route`: Can be either "my" or "owned". "my" refers to communities you are a member of, while "owned" refers to communities you own. (Optional, default is "my")
- `Delay`: Specifies the wait time in milliseconds (ms) between requests. This can be adjusted based on your server's response time. (Optional, default is 0 ms)

```powershell
.\clone_allCommunitys.ps1 "Route" "Delay"
```

## How to Obtain Your LtpaToken2
1. Navigate to the community page.
2. Press `F12` to open the developer tools. (Note: Be cautious when using developer tools, especially if instructed by someone untrusted.)
3. Go to the "Network" tab.
4. Refresh the page by pressing `F5`.
5. Click on the first item in the list that appears.
6. In the details pane that opens, find and click on "Cookies". (You might need to double-click.)
7. Look for the "LtpaToken2" cookie. Right-click the value next to it and select "Copy".
8. Create a file named `ltpaToken.txt` in the same directory as this script and paste your copied token there.


## Notes
- Ensure you have the necessary permissions on both the source and target communities for cloning.
- Review and test the script in a safe environment before using it in a production setting.

We hope this tool enhances your HCL Connections experience by simplifying the process of managing community content. For any issues or contributions, please feel free to submit an issue or pull request on GitHub.
