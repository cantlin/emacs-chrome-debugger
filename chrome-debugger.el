(require 'json)

(defcustom chrome-debugger-host "localhost"
  "Hostname of the server running ChromeDevTools."
  :group 'chrome-debugger
  :type 'string)

(defcustom chrome-debugger-port 9222
  "Port for the server running ChromeDevTools."
  :group 'chrome-debugger
  :type 'integer)

(defvar chrome-debugger-buffer-name "*chrome-debugger*"
  "Name of the chrome-debugger buffer.")

(defvar chrome-debugger-stream-name "chrome-debugger"
  "Name of the chrome-debugger network stream.")

(defmacro in-chrome-debugger-buffer (body)
  `(save-excursion
     (set-buffer chrome-debugger-buffer)
     ,body))

(defun chrome-debugger-send (process str)
  "Send string to process and insert it into the current buffer."
  (process-send-string process str)
  (insert (format "-- Sent --\n%s\n" str)))

(defun chrome-debugger-read (process str)
  "Receive string from process and insert it into the chrome-debugger buffer."
  (if (not (eq str "ChromeDevToolsHandshake\r\n"))
    (progn
      (setq chrome-debugger-last-response (json-read-from-string (car (last (split-string str "\n\n")))))
      (in-chrome-debugger-buffer
        (insert (format "-- Received --\n%s\n" chrome-debugger-last-response))))))

(defun chrome-debugger-formatted-request (command tool &optional destination)
  "Send a formatted request to the ChromeDevTools server."
  (chrome-debugger-send chrome-debugger-stream
    (format (concat "Content-Length:%d\r\n"
                    "Tool:%s\r\n"
                    "Destination:%s\r\n"
                    "\r\n"
                    "%s")
            (length command) tool (if (boundp 'destination) destination "") command)))

(defun chrome-debugger-devtools-command (command)
  "Send an arbitrary command to the DevToolsService.
   Available commands: `ping`, `version`, `list_tabs`."
  (interactive "sCommand: ")
  (in-chrome-debugger-buffer
    (chrome-debugger-formatted-request (format "{\"command\":\"%s\"}" command) "DevToolsService")))

(defun chrome-debugger-v8-command (command destination)
  "Send an arbitrary command to the V8Debugger."
  (interactive "sCommand: \nsDestination: ")
  (in-chrome-debugger-buffer
    (chrome-debugger-formatted-request command "V8Debugger" destination)))

(defun chrome-debugger-reload-first-tab () ""
  (interactive)
  (chrome-debugger-devtools-command 'list_tabs)
  (accept-process-output chrome-debugger-stream)
  (chrome-debugger-v8-command
    (json-encode '((command . "evaluate_javascript") (data . "window.location.reload();")))
    (aref (aref (cdr (assoc 'data chrome-debugger-last-response )) 0) 0)))
 
(setq chrome-debugger-buffer (get-buffer-create chrome-debugger-buffer-name))
(if (not (boundp 'chrome-debugger-stream))
  (progn
    (setq chrome-debugger-stream (open-network-stream
                                  chrome-debugger-stream-name
                                  chrome-debugger-buffer
                                  chrome-debugger-host
                                  chrome-debugger-port))
    (set-process-filter-multibyte chrome-debugger-stream t)
    (set-process-coding-system chrome-debugger-stream 'utf-8 'utf-8)
    (set-process-filter chrome-debugger-stream 'chrome-debugger-read)
    (setq chrome-debugger-last-response nil)
    (in-chrome-debugger-buffer
      (chrome-debugger-send chrome-debugger-stream "ChromeDevToolsHandshake\r\n"))))
