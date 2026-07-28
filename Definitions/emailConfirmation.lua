--- @class emailConfirmation Client side of the email confirmation (double opt-in) feature. Talks to the email-service Cloudflare Worker and to the current user's /users/{uid} cloud document.
emailConfirmation = {}

--- RequestEmail: Requests (or resends) a confirmation email for the given address via POST /email/request. The current Firebase ID token is attached as a Bearer token automatically. On completion the 'complete' callback is invoked with a table describing the result (the parsed JSON body plus an httpStatus field). On a 401 the ID token is force-refreshed and the request retried once.
--- @param args {email: string, complete: nil|fun(result: {ok: boolean, status: nil|string, error: nil|string, retryAfterSeconds: nil|number, httpStatus: number})}
function emailConfirmation.RequestEmail(args)
	-- dummy implementation for documentation purposes only
end

--- MonitorStatus: Starts a realtime listener on the current user's /users/{uid} document. The callback fires with the current email/emailConfirmed/allowEmails whenever they change in the cloud (including the initial load). Returns a handle; call handle:Stop() to unsubscribe.
--- @param callback fun(state: {email: nil|string, emailConfirmed: boolean, allowEmails: boolean})
function emailConfirmation.MonitorStatus(callback)
	-- dummy implementation for documentation purposes only
end

--- SetAllowEmails: Writes the user's email opt-in preference to /users/{uid}/allowEmails. Only meaningful once the email has been confirmed (emailConfirmed == true).
--- @param value any
--- @return nil
function emailConfirmation.SetAllowEmails(value)
	-- dummy implementation for documentation purposes only
end
