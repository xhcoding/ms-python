;;; ms-python.el --- A lsp client for microsoft python language server.    -*- lexical-binding: t; -*-

;; Filename: ms-python.el
;; Description: A lsp client for microsoft python language server.
;; Package-Requires: ((emacs "26.1") (lsp-mode "5.0"))
;; Author: Yong Cheng <xhcoding@163.com>
;; Created: 2018-11-22 08:16:00
;; Version: 1.0
;; Last-Update: 2018-03-18 12:00
;; URL: https://github.com/xhcoding/ms-python
;; Keywords: tools
;; Compatibility: GNU Emacs 26.1

;;; This file is NOT part of GNU Emacs

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;; Please read README.org

;;; Require:

(require 'lsp)
(require 'python)
(require 'json)
(require 'subr-x)

;;; Code:
;;

(defgroup ms-python nil
  "Microsoft python language server adapter for LSP mode."
  :prefix "ms-python-"
  :group 'python
  :link '(url-link :tag "GitHub" "https://github.com/xhcoding/ms-python"))

;;; Custom:
(defcustom ms-python-server-install-dir
  (locate-user-emacs-file "ms-pyls/server/")
  "Install directory for microsoft python language server."
  :group 'ms-python
  :risky t
  :type 'directory)

(defcustom ms-python-dotnet-install-dir
  (locate-user-emacs-file "ms-pyls/dotnet/")
  "Install directory for dotnet."
  :group 'ms-python
  :risky t
  :type 'directory)

(defcustom ms-python-database-dir
  "DefaultDB"
  "Cache data storge directory.
It is relative to `ms-python-server-install-dir',You can set a absolute path."
  :group 'ms-python
  :risky t
  :type 'directory)

(defcustom ms-python-python-lint-enabled t
  "Enable or disable lint."
  :group 'ms-python
  :type 'boolean)

(defcustom ms-python-analysis-errors []
  "Diagnostics which should be shown as errors."
  :group 'ms-python
  :type '(repeat string))

(defcustom ms-python-analysis-warnings []
  "Diagnostics which should be shown as warnings."
  :group 'ms-python
  :type '(repeat string))

(defcustom ms-python-analysis-information []
  "Diagnostics which should be shown as informational."
  :group 'ms-python
  :type '(repeat string))

(defcustom ms-python-analysis-disabled []
  "Diagnotics which should not be shown at all."
  :group 'ms-python
  :type '(repeat string))


;;; Function:

(defun ms-python--locate-server()
  "Return the path of the server startup entry file.
Its name is \"Microsoft.Python.LanguageServer.dll\".
If not found, ask the user whether to install."
  (let* ((server-dir ms-python-server-install-dir)
         (server-entry (expand-file-name "Microsoft.Python.LanguageServer.dll" server-dir)))
    (unless (file-exists-p server-entry)
      (if (yes-or-no-p "Microsoft Python Language Server is not installed. Do you want to install it?")
          (ms-python--ensure-server)
        (error "Cannot start microsoft python language server without server be installed!")))
    server-entry))

(defun ms-python--locate-dotnet()
  "Return dotnet's path.If not found, ask the user whether to install."
  (let ((dotnet-exe (or
                     (and (file-directory-p ms-python-dotnet-install-dir)
                          (car (directory-files ms-python-dotnet-install-dir t "^dotnet\\(\\.exe\\)?$"))) ;; Specified installation path
                     (executable-find "dotnet"))))                               ;; System path
    (unless (and dotnet-exe
                 (not (string-empty-p (shell-command-to-string (format "%s --list-runtimes" dotnet-exe))))
                 (not (string-empty-p (shell-command-to-string (format "%s --list-sdks" dotnet-exe)))))
      (error "Dotnet sdk not found!")
      )
    dotnet-exe))

(defun ms-python--ensure-server()
  "Ensure Microsoft Python Language Server."
  (let* ((dotnet (ms-python--locate-dotnet))
         (default-directory ms-python-server-install-dir)
         (command)
         (log))
    (when (file-directory-p default-directory)
      (delete-directory default-directory t))
    (mkdir default-directory t)
    (setq command "git clone --depth 1 https://github.com/Microsoft/python-language-server.git")
    (message "Clone server source: %s" command)
    (setq log (shell-command-to-string command))
    (message "%s\n" log)
    (setq command (format "%s build -c Release  python-language-server/src/LanguageServer/Impl" dotnet))
    (message "build server: %s" command)
    (setq log (shell-command-to-string command))
    (message "%s\n" log)
    (with-temp-buffer
      (insert log)
      (goto-char (point-min))
      (unless (search-forward-regexp "Build succeeded." nil t)
        (error "Build server failed!You can check log message in *MESSAGE* buffer!"))
      (copy-directory "python-language-server/output/bin/Release" default-directory t t t)
      (when (file-directory-p "python-language-server")
        (delete-directory "python-language-server" t))
      (message "Build server finished.")
      )))

(defun ms-python-update-server ()
  "Update Microsoft python language server."
  (interactive)
  (message "Server update started...")
  (ms-python--ensure-server)
  (message "Server update finished..."))

(defun ms-python--ls-command()
  "LS startup command."
  (let ((dotnet (ms-python--locate-dotnet))
        (server (ms-python--locate-server)))
    `(,dotnet
      ,server)))

(defun ms-python--publish-server-started(_workspace _params)
  "Publish server started."
  (message "Microsoft python language server started!"))

(defun ms-python--get-python-env()
  "Return list with pyver-string and json-encoded list of python search paths."
  (let ((python (executable-find python-shell-interpreter))
        (ver "import sys; print(f\"{sys.version_info[0]}.{sys.version_info[1]}\");")
        (sp (concat "import json; sys.path.insert(0, '" default-directory "'); print(json.dumps(sys.path))")))
    (with-temp-buffer
      (call-process python nil t nil "-c" (concat ver sp))
      (let ((seq (split-string (buffer-string) "\n")))
        `(,(nth 0 seq) ,(nth 1 seq))))))

;; I based most of this on the vs.code implementation:
;; https://github.com/Microsoft/vscode-python/blob/master/src/client/activation/languageServer/languageServer.ts#L219
;; (it still took quite a while to get right, but here we are!)
(defun ms-python--initialization-options ()
  "Return initialization-options for LP startup."
  (let* ((python-env (ms-python--get-python-env))
         (pyver (nth 0 python-env))
         (pysyspath (nth 1 python-env)))
    `(:interpreter (
                    :properties (
                                 :InterpreterPath ,(executable-find python-shell-interpreter)
                                 :DatabasePath ,(file-name-as-directory (expand-file-name ms-python-database-dir ms-python-server-install-dir))
                                 :Version ,pyver))
                   ;; preferredFormat "markdown" or "plaintext"
                   ;; experiment to find what works best -- over here mostly plaintext
                   :displayOptions (
                                    :preferredFormat "plaintext"
                                    :trimDocumentationLines :json-false
                                    :maxDocumentationLineLength 0
                                    :trimDocumentationText :json-false
                                    :maxDocumentationTextLength 0)
                   :searchPaths ,(json-read-from-string pysyspath))))

(defun ms-python--doc-filter-CM (doc)
  "Filter  from DOC on Windows."
  (when (and (eq system-type 'windows-nt) doc)
    (replace-regexp-in-string "" "" doc)))

;; lsp-ui-doc--extract gets called when hover docs are requested
;; as always, we have to remove Microsoft's unnecessary some entities
;; Windows only

(when (eq system-type 'windows-nt)
  (advice-add 'lsp-ui-doc--extract
              :filter-return #'ms-python--doc-filter-CM)

  (advice-add 'lsp-ui-sideline--format-info
              :filter-return #'ms-python--doc-filter-CM))

(lsp-register-custom-settings
 '(("python.linting.enabled" ms-python-python-lint-enabled t)
   ("python.analysis.errors" ms-python-analysis-errors)
   ("python.analysis.warnings" ms-python-analysis-warnings)
   ("python.analysis.information" ms-python-analysis-information)
   ("python.analysis.disabled" ms-python-analysis-disabled)))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection #'ms-python--ls-command)
  :major-modes '(python-mode)
  :server-id 'ms-python
  :notification-handlers
  (lsp-ht ("python/languageServerStarted" #'ms-python--publish-server-started)
          ("python/reportProgress" 'ignore)
          ("python/beginProgress" 'ignore)
          ("python/endProgress" 'ignore))
  :initialization-options #'ms-python--initialization-options
  :initialized-fn (lambda(workspace)
                    (with-lsp-workspace workspace
                      (lsp--set-configuration (lsp-configuration-section "python"))))
  ))


(provide 'ms-python)
;;; ms-python.el ends here
