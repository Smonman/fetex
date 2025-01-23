<#
	.SYNOPSIS
	Sets up a new Latex project based on public temlpates from GitHub.

	.DESCRIPTION
	This script downloads given Latex templates from GitHub and compiles their
	files into a single specified destination location. The templates are
	downloaded via the latest release from the GitHub repository.

	Please note, that this script only suports GitHub repositories with a ZIP
	archive release. This script is written primarily to support my own
	templates, support of other templates is not provided, but it may work.

	.PARAMETER User
	The GitHub user the different Latex template repositories belong to. This
	parameter is optional. If Latex templates from different users are needed,
	this parameter can be left unused, as user definitions can also be done when
	specifing the repositories.

	.PARAMETER RepoStrings
	This is a list of repository names. Each entry in this list has a specific
	format as a user-repository-name-pair: [<user-name>/]<repository-name>. The
	user part is optional, while the repository name is required.

	If the user is not given, the value from the User parameter is used instead.
	
	It is possible to mix entries with and without a user.

	.PARAMETER Destination
	The location where the project should be set up. This parameter is defaulted
	to the current location if not present.

	.EXAMPLE
	PS> fetex.ps1 -User Smonman -RepoStrings tuwien-assignment-template,moderncode

	.EXAMPLE
	PS> fetex.ps1 -RepoStrings Smonman/tuwien-assignment-template,abc/my-repo -Destination C:/
#>
[CmdletBinding(SupportsPaging = $false, SupportsShouldProcess = $false, PositionalBinding = $false)]
param(
	[Parameter(Mandatory = $false)]
	[ValidateNotNullOrWhiteSpace()]
	[string]
	$User = "Smonman",
	[Parameter(Mandatory = $true)]
	[ValidateCount(1, 20)]
	[string[]]
	$RepoStrings,
	[Parameter(Mandatory = $false)]
	[ValidateNotNullOrWhiteSpace()]
	[string]
	$Destination = $(Get-Location)
)

<#
	.DESCRIPTION
	This holds data to a specific GitHub repository.

	.PARAMETER User
	The GitHub username

	.PARAMETER Repo
	The GitHub repository name that belongs to the given user
#>
class RepoDescriptor {

	[ValidateNotNullOrWhiteSpace()]
	[string]
	$User
	[ValidateNotNullOrWhiteSpace()]
	[string]
	$Repo

	RepoDescriptor($User, $Repo) {
		$this.User = $User
		$this.Repo = $Repo
	}
}

<#
	.SYNOPSIS
	This downloads the latest release from the given GitHub repository.
	The download will be stored as a temporary file.

	.DESCRIPTION
	Internally, three calls to the GitHub API are used to get the download link
	of the latest release of the given repository. Please note, that GitHub has
	a rate limit on these calls, which will result in an error if exeeded.

	The lates release will be downloaded and stored as a temporary file. The
	path to this file will then be returned.

	.PARAMETER RepoDescriptor
	A repository descriptor holding information about the repository where the
	latest release should be downloaded from.

	.OUTPUTS
	A path to the downloaded file.

	.Link
	RepoDescriptor
#>
function Get-FetexLatestRelease {

	[OutputType('string')]
	[CmdletBinding(SupportsPaging = $false, SupportsShouldProcess = $false, PositionalBinding = $false)]
	param(
		[Parameter(Mandatory = $true)]
		[RepoDescriptor]
		$RepoDescriptor
	)

	process {
		Write-Information "Fetching latest release from 'https://api.github.com/repos/$($RepoDescriptor.User)/$($RepoDescriptor.Repo)/releases/latest'"
		try {
			$assetsUrlObj = Invoke-RestMethod -Uri "https://api.github.com/repos/$($RepoDescriptor.User)/$($RepoDescriptor.Repo)/releases/latest" | Select-Object "assets_url"
		}
		catch [System.Exception] {
			Write-Error "Could not fetch the asset URL of Repo '$($RepoDescriptor.Repo)'"
			throw $_.Exception
		}

		Write-Information "Fetching assets from '$($assetsUrlObj.assets_url)'"
		try {
			$downloadUrlObj = Invoke-RestMethod -Uri "$($assetsUrlObj.assets_url)" | Select-Object -First 1
		}
		catch [System.Exception] {
			Write-Error "Could not fetch the download URL of Repo '$($RepoDescriptor.Repo)'"
			throw $_.Exception
		}

		Write-Information "Downloading latest release from '$($downloadUrlObj.browser_download_url)'"
		$downloadPath = $([System.IO.Path]::GetTempFileName())

		Write-Information "Downloading to '${downloadPath}'"
		try {
			(New-Object System.Net.WebClient).DownloadFile("$($downloadUrlObj.browser_download_url)", $downloadPath)
		}
		catch [System.Exception] {
			Write-Error "Could not download latest release of Repo '${Repo}'"
			throw $_.Exception
		}

		Write-Information "Finished downloading"
		return $downloadPath
	}
}

<#
	.SYNOPSIS
	This downloads the latest releases from the given GitHub repositories.

	.DESCRIPTION
	This is a simple adaptation of Get-FetexLatestRelease that handles multiple
	repositories.

	.PARAMETER RepoDescriptors
	An array of repository descriptors holding information about the repository
	from which the latest release should be downloaded from.

	.OUTPUTS
	An array of paths to the downloaded files.

	.Link
	Get-FetexLatestRelease

	.Link
	RepoDescriptor
#>
function Get-FetexLatestReleases {
	[OutputType('string[]')]
	[CmdletBinding(SupportsPaging = $false, SupportsShouldProcess = $false, PositionalBinding = $false)]
	param(
		[Parameter(Mandatory = $true)]
		[RepoDescriptor[]]
		$RepoDescriptors
	)

	$result = New-Object System.Collections.Generic.List[string]
	foreach ($repoDescriptor in $RepoDescriptors) {
		$result.Add((Get-FetexLatestRelease -RepoDescriptor $repoDescriptor))
	}
	return $result
}

<#
	.SYNOPSIS
	Converts a string of the format [<user-name>/]<repository-name> to a
	RepoDescriptor.

	.DESCRIPTION
	A repo string usually holds two pieces of information, a GitHub username and
	a GitHub repository name. These two fields are separated by a forward slash.

	The username together with the forward slash may be omitted. If no user is
	given in the repo string, then the user supplied via the User parameter will
	be used instead.

	If the User parameter is not given, and no user is supplied by the repo
	string an exception will be thrown.

	.PARAMETER User
	The GitHub username as a string. This parameter is not mandatory.

	.PARAMETER RepoString
	An array of repo strings of the aforementioned format

	.OUTPUTS
	An array of converted RepoDescriptors

	.LINK
	RepoDescriptor
#>
function Convert-FetexRepoString {
	[OutputType('RepoDescriptor[]')]
	[CmdletBinding(SupportsPaging = $false, SupportsShouldProcess = $false, PositionalBinding = $false)]
	param(
		[Parameter(Mandatory = $false)]
		[string]
		$User,
		[Parameter(Mandatory = $true)]
		[string[]]
		$RepoString
	)

	$repos = New-Object System.Collections.Generic.List[RepoDescriptor]
	foreach ($repoString in $RepoString) {
		if ($repoString.Contains("/")) {
			$userTmp = $repoString.Substring(0, $repoString.IndexOf("/"))
			$repoTmp = $repoString.Substring($repoString.IndexOf("/") + 1)
			if ($userTmp.Length -eq 0) {
				if ($null -eq $User) {
					Write-Error "No user supplied"
					throw "User is null"
				}
				$userTmp = $User
			}
			$repos.Add([RepoDescriptor]::new($userTmp, $repoTmp))
		}
		else {
			$repos.Add([RepoDescriptor]::new($User, $repoString))
		}
	}
	return $repos
}

<#
	.SYNOPSIS
	Creates a new temporary directory with a unique name.

	.DESCRIPTION
	Creates a new directory in the systems temporary files folder, with a unique
	name.

	.OUTPUTS
	The path to the newly created temporary directory

	.LINK
	[System.IO.Path]::GetTempPath()
#>
function New-TemporaryDirectory {
	$parent = [System.IO.Path]::GetTempPath()
	do {
		$item = New-Item -Path $parent -Name $(New-Guid) -ItemType "directory" -ErrorAction SilentlyContinue
	} while (-not $item)
	return $item.FullName
}

<#
	.SYNOPSIS
	Expands a downloaded repository into a temporary directory.
	
	.DESCRIPTION
	Expands each ZIP archive into its own temporary directory and returns the
	paths to each of them. The order will be maintained.

	.PARAMETER Path
	An array of paths to ZIP archives which should be expanded into a temporary
	directory.

	.OUTPUTS
	An array of paths to the expanded ZIP archives

	.LINK
	Expand-Archive
#>
function Expand-FetexRepo {
	[OutputType('string[]')]
	[CmdletBinding(SupportsPaging = $false, SupportsShouldProcess = $false, PositionalBinding = $false)]
	param(
		[Parameter(Mandatory = $true)]
		[string[]]
		$Path
	)

	$results = New-Object System.Collections.Generic.List[string]
	foreach ($path in $Path) {
		$destinationPath = New-TemporaryDirectory
		Expand-Archive -LiteralPath $(Convert-Path $path) -DestinationPath $destinationPath
		$results.Add($destinationPath);
	}
	return $results
}

<#
	.SYNOPSIS
	Merges multiple expanded repositories into a single destination location.

	.DESCRIPTION
	Copies each file of the given paths into a destination location. If a file
	already exists at the destination, the user may select an action for the
	copied file to take.

	The destination path must already exist prior to the execution of this
	function.

	.PARAMETER Path
	An array of source paths from which files should be copied.

	.PARAMETER Destination
	An existing destination path to which all the repositories should be merged
	into.
#>
function Merge-FetexRepos {
	[CmdletBinding(SupportsPaging = $false, SupportsShouldProcess = $false, PositionalBinding = $false)]
	param(
		[Parameter(Mandatory = $true)]
		[string[]]
		$Path,
		[Parameter(Mandatory = $true)]
		[string]
		$Destination
	)

	if (!(Test-Path -Path $Destination)) {
		Write-Error "Path '${Destination}' does not exist"
		throw $_.Exception
	}

	foreach ($path in $Path) {
		foreach ($item in (Get-ChildItem -Path $path -Force)) {
			Write-Information "Copying file '${item}' to '${Destination}'"
			$expectedDestinationPath = Join-Path $Destination ($item.Name)
			if (!(Test-Path -Path $expectedDestinationPath)) {
				Copy-Item -LiteralPath $(Convert-Path $item) -Destination $Destination
			}
			else {
				Write-Warning "File '${item}' already exists at '${Destination}'"
				$choices = @(
					[System.Management.Automation.Host.ChoiceDescription]::new("&Override", "Override any existing file"),
					[System.Management.Automation.Host.ChoiceDescription]::new("&Ignore", "Don't copy and continue with the next file"),
					[System.Management.Automation.Host.ChoiceDescription]::new("&Concat", "Concat the files contents to one file")
				)
				$userSelection = $host.UI.PromptForChoice('Select Option', 'An item already exists at the destination. Should the file be overridden or its contents concatinated?', $choices, 1)
				switch ($userSelection) {
					0 {
						Write-Information "Force copying file '${item}' to '${Destination}'"
						Copy-Item -LiteralPath $(Convert-Path $item) -Destination $Destination -Force
					}
					1 {
						continue
					}
					2 {
						Write-Information "Concatinating '${expectedDestinationPath}' and '${item}' to '${expectedDestinationPath}'"
						Add-Content -Path $expectedDestinationPath -Value (Get-Content $item)
					}
				}
			}
		}
	}
}

$repos = Convert-FetexRepoString -User $User -RepoString $RepoStrings
$templates = Get-FetexLatestReleases -RepoDescriptors $repos
$directories = Expand-FetexRepo -Path $templates
Merge-FetexRepos -Path $directories -Destination $Destination
