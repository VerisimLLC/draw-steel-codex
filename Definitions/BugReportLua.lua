--- @class BugReportLua An in-progress bug report created with dmhub.BeginBugReport(). Holds the screenshot captured when the report was begun and can upload the report with Submit.
--- @field screenshotImage nil|string (Read-only) An image id for the screenshot captured when the report was begun, suitable for use as a panel bgimage. nil if the screenshot could not be captured.
--- @field screenshotWidth number (Read-only) The width in pixels of the captured screenshot, or 0 if none.
--- @field screenshotHeight number (Read-only) The height in pixels of the captured screenshot, or 0 if none.
--- @field discordUsername nil|string (Read-only) The local user's Discord username, if the Discord desktop client is running and connected, or nil. When present the report dialog can offer to include it (pass contactOnDiscord=true to Submit) so developers can follow up with the reporter on Discord.
BugReportLua = {}

--- Begin
--- @param callback any
--- @return nil
function BugReportLua.Begin(callback)
	-- dummy implementation for documentation purposes only
end

--- Cancel: Abandons the report, releasing the captured screenshot.
--- @return nil
function BugReportLua:Cancel()
	-- dummy implementation for documentation purposes only
end

--- Submit: Uploads the report. type is a short string categorizing the report ('bug', 'feature' or 'feedback'; defaults to 'bug'). includeLog defaults to true and also uploads the previous session's log (Player-prev.log) when present; includeScreenshot defaults to false; allowGameEntry defaults to true. contactOnDiscord defaults to false; when true and a Discord username is available (see discordUsername) it is written to the report so developers can follow up on Discord. mood is an optional short string ('angry', 'frustrated', 'sad', 'happy' or 'delighted') recording how the user feels; omitted from the record when nil/empty. attachments is a list of file paths to upload with the report. progress is called with 0-1 as uploads proceed; complete is called with the new report id; error is called with a message if the submission fails (after which Submit may be called again).
--- @param options {description: string, type: nil|string, includeLog: nil|boolean, includeScreenshot: nil|boolean, allowGameEntry: nil|boolean, contactOnDiscord: nil|boolean, mood: nil|string, attachments: nil|string[], progress: nil|fun(ratio: number), complete: nil|fun(reportid: string), error: nil|fun(message: string)}
function BugReportLua:Submit(options)
	-- dummy implementation for documentation purposes only
end
