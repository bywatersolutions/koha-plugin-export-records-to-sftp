# Koha Export Records to SFTP Plugin

This Koha plugin allows you to schedule the export of bibliographic records and upload them to a remote FTP or SFTP server. It wraps the `misc/export_records.pl` script, providing a flexible interface for defining multiple export jobs.

## Features

-   **Multiple Export Jobs:** Configure an unlimited number of export jobs with different settings.
-   **Protocol Support:** Supports both FTP and SFTP for file uploads.
-   **Flexible Selection:** Select records based on date (last N days), record ID range, or specific record IDs.
-   **Report Integration:** Use a saved Koha report to generate the list of record IDs to export.
-   **Format Control:** Choose between MARC (ISO 2709) and XML formats.
-   **Item Data:** Option to include or exclude item data in the export.
-   **Item Type Filtering:** Filter exports by specific item types.
-   **Automated Execution:** Runs nightly via the Koha plugin system's `cronjob_nightly` hook.

## Installation

1.  Download the latest `.kpz` release from the [releases page](https://github.com/bywatersolutions/koha-plugin-export-records-to-sftp/releases).
2.  In your Koha staff client, go to **Administration > Plugins > Manage plugins**.
3.  Click **Upload plugin**.
4.  Select the downloaded `.kpz` file and click **Upload**.

## Configuration

1.  Go to **Actions > Configure** for the "Export Records to SFTP" plugin.
2.  Click **Add New Job** to create a new export configuration.
3.  Fill in the job details:
    -   **Remote Host:** The hostname or IP address of the FTP/SFTP server.
    -   **Remote Path:** The directory on the remote server where files should be uploaded.
    -   **Username/Password:** Credentials for the remote server.
    -   **Protocol:** Select FTP or SFTP.
    -   **Format:** Select MARC or XML.
    -   **Filename:** Pattern for the output filename. Supports `timestamp` replacement.
    -   **Record Type:** bibs or auths.
    -   **Days Back:** Number of days of history to export (based on timestamp).
    -   **Min/Max ID:** Range of record IDs to export.
    -   **Record IDs:** Comma-separated list of specific IDs.
    -   **Report ID:** The ID of a saved SQL report that returns a list of record IDs (one per row).
    -   **Item Type:** Filter by specific item type (e.g., BOOK).
    -   **Don't Export Items:** Check to exclude item data.
4.  Click **Save Configuration**.

## License

This plugin is released under the AGPL v3 license.
