;;; org-dropbox.el --- move notes from phone through Dropbox into org-mode datetree

;;; Copyright (C) 2014 Heikki Lehvaslaiho <heikki.lehvaslaiho@gmail.com>

;; URL: https://github.com/heikkil/org-dropbox
;; Author: Heikki Lehvaslaiho <heikki.lehvaslaiho@gmail.com>
;; Version: 20140923
;; Package-Requires: ((org-mode "8.2") (emacs "24"))
;; Keywords: Dropbox Android notes org-mode

;;; (names "0.5") ?http://endlessparentheses.com/introducing-names-practical-namespaces-for-emacs-lisp.html

;;; Commentary:
;;
;; ** Justification
;;
;; I wanted to collect together all interesting articles I saw reading
;; news on my phone applications. I was already using Org mode to keep
;; notes in my computer.
;;
;; The [[http://orgmode.org/manual/MobileOrg.html][MobileOrg]] app in
;; my Android phone is fiddly and does not do things the way I want,
;; so this was a good opportunity to learn lisp while doing something
;; useful.
;;
;; ** Sharing notes
;;
;; On Android phones, installing Dropbox client also adds Dropbox as
;; one of the applications that can be used to share articles from
;; many news applications (e.g. BBC World News, Flipboard). In
;; contrast to many other options, Dropbox saves these links as plain
;; text files -- a good starting point for including them into
;; org-mode.
;;
;; Org mode has a date-ordered hierachical file structure called
;; datetree that is ideal for storing notes and links. This
;; org-dropbox-mode code reads each note in the Dropbox notes folder,
;; formats them to an org element, and refiles them to a correct place
;; in a datetree file for easy searching through org-agenda commands.
;;
;; Each new org headline element gets an inactive timestamp that
;; corresponds to the last modification time of the note file.
;;
;; The locations in the filesystem are determined by two customizable
;; variables -- by default both pointing inside Dropbox:
;;
;; #+BEGIN_EXAMPLE
;;   org-dropbox-note-dir      "~/Dropbox/notes/"
;;   org-dropbox-datetree-file "~/Dropbox/org/reference.org"
;; #+END_EXAMPLE
;;
;; Since different programmes format the shared link differently, the
;; code tries its best to make sense of them. A typical note has the
;; name of the article in the first line and the link following it
;; separated by one or two newlines. The name is put to the header,
;; multiple new lines are reduced to one, and the link is followed by
;; the timestamp. If the title uses dashes (' - '), exclamation marks
;; ('! '), or colons (': '), they are replaced by new lines to wrap
;; the trailing text into the body. In cases where there is no text
;; before the link, the basename of the note file is used as the
;; header.
;;
;; After parsing, the source file is removed from the note directory.
;;
;; Note that most of the time the filename is ignored. The only
;; absolute requirement for the filename is that it has to be unique
;; within the directory. Filename is used as an entry header only if
;; the file does not contain anything usefull, i.e. the content is
;; plain URL.
;;
;; ** Usage
;;
;; Set up variables =org-dropbox-note-dir= and
;; =org-dropbox-datetree-file= to your liking. Authorize your devices
;; to share that Dropbox directory. As long as you save your notes in
;; the correct Dropbox folder, they are copied to your computer for
;; processing and deletion.
;;
;; The processing of notes starts when you enable the minor mode
;; org-dropbox-mode in Emacs, and stops when you disable it. After
;; every refiler run, a message is printed out giving the number of
;; notes processed.
;;
;; An internal timer controls the periodic running of the notes
;; refiler. The period is set in customizable variable
;; =org-dropbox-refile-timer-interval= to run by default every hour
;; (3600 seconds).
;;
;; ** Disclaimer
;;
;; This is first time I have written any reasonable amount of lisp
;; code, so writing a whole package was a jump in the dark. The code has
;; been running reliably for some time now, but if you want to try the
;; code and be absolutely certain you do not lose your notes, comment
;; expression =(delete-file file)= from the code.
;;
;; There are undoubtedly many things that can be done better. Feel
;; free to raise issues and submit pull requests.
;;
;;
;; This file is not a part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'org)

;;;###autoload
(define-minor-mode org-dropbox-mode
  "Minor mode adding Dropbox notes to datetree.

With no argument, this command toggles the mode. Non-null prefix
argument turns on the mode. Null prefix argument turns off the
mode.
"
  ;; The initial value - Set to 1 to enable by default
  :init-value nil
  ;; The indicator for the mode line.
  :lighter " Org-Dbox"
  :global 1
  ;; The minor mode keymap - examples
  :keymap  `(
            ;; (,(kbd "C-c C-a") . some-command)
            ;; (,(kbd "C-c C-b") . other-command)
            ;; ("\C-c\C-c" . "This works too")
             )
  (if org-dropbox-mode
      (org-dropbox-refile-timer-start)
    (org-dropbox-refile-timer-stop)))

(defconst org-dropbox-version "20140923"
  "Version for org-dropbox")

(defcustom org-dropbox-note-dir "~/Dropbox/notes/"
  "Directory where Dropbox shared notes are added."
  :group 'org
  :type 'directory)

(defcustom org-dropbox-datetree-file "~/Dropbox/org/reference.org"
  "File containing the datetree file to store formatted notes."
  :group 'org
  :type 'file)

(defcustom org-dropbox-refile-timer-interval (* 60 60)
  "Repeat refiling every N seconds. Defaults to 3600 sec = 1 h"
  :group 'org
  :type 'int)

(defun org-dropbox-datetree-file-entry-under-date (txt date)
  "Insert a node TXT into the date tree under DATE.

Original - and functional - version of the
`org-datetree-file-entry-under' function in org-datetree.el.
from xxxxx
Only slightly modified.
But, see the code about subtrees..."
  (org-datetree-find-date-create
   (list (nth 4 date) (nth 3 date) (nth 5 date)))
  (show-subtree)
  (next-line)
  (beginning-of-line)
  (insert txt))

(defun org-dropbox-get-mtime (buffer-file-name)
  "Get the modification time of a file (BUFFER-FILE-NAME)."
  (let* ((attrs (file-attributes (buffer-file-name)))
         (mtime (nth 5 attrs)))
    (format-time-string "%Y-%m-%d %T" mtime)))

(defun org-dropbox-notes-to-datetree (dirname buffername)
  "Process files in a directory DIRNAME and place the entries to BUFFERNAME."
  (let (files file file-content mtime lines header entry date counter)
    (setq counter 0)
    (setq files (directory-files dirname t "\\.txt$"))
    (while files
      (setq file (pop files))
      (setq file-content (with-current-buffer
                             (find-file-noselect file)
                           (buffer-string)))
      (setq mtime (org-dropbox-get-mtime file))

      ;; massage the contents into list of lines -- optimise later
      ;;
      ;; remove tabs
      (setq file-content (replace-regexp-in-string "\t" "" file-content))
      ;; split some long title lines
      (setq file-content (replace-regexp-in-string " ?[-!:|] " "\n" file-content))
      ;; separate link from title
      (setq file-content (replace-regexp-in-string " *http:" "\nhttp:" file-content))
      ;; remove newly added new lines from the beginning of the string, if any
      (setq file-content (replace-regexp-in-string "^\\(\n\\).*\\'" "" file-content nil nil 1))
      ;; remove successive newlines
      (setq lines (split-string (replace-regexp-in-string "\n+" "\n" file-content) "\n"))

      ;; create header text into first element of lines
      (if (equal (length lines) 1)
          (setq lines (cons (concat "**** "
                                    (file-name-sans-extension (file-name-nondirectory file)))
                            lines))
        (setcar lines (concat "**** " (car lines))))
      ;; create the entry string
      (setq entry
            (mapconcat 'identity
                       (append lines
                               (list (concat "Entered on [" mtime "]\n")))
                       "\n"))

      ;; save in the datetree
      (setq date (decode-time (org-read-date nil t mtime nil)))
      (with-current-buffer buffername
        (barf-if-buffer-read-only)
        (org-dropbox-datetree-file-entry-under-date entry date))
      (setq counter (1+ counter))
      (delete-file file))
    (with-current-buffer buffername (save-buffer))
    (when (> counter 0)
      (message "org-dropbox: processed %d notes" counter))))

(defun org-dropbox-refile-notes ()
  "Create `org-mode' entries from DropBox notes and place them in a datetree."
  (interactive)
  (let (buffername)
    (when (file-exists-p org-dropbox-datetree-file)
      (setq buffername (buffer-name (find-file-noselect org-dropbox-datetree-file)))
      (org-dropbox-notes-to-datetree org-dropbox-note-dir buffername))))

(defun org-dropbox-refile-timer-start ()
  "Start running the refiler while pausing for given interval.

The variable org-dropbox-refile-timer-interval determines the
repeat interval. The value is in seconds."
  (setq org-dropbox-refile-timer
        (run-with-timer 0
                        org-dropbox-refile-timer-interval
                        'org-dropbox-refile-notes)))

(defun org-dropbox-refile-timer-stop ()
  "Stop running the refiler."
  (cancel-timer org-dropbox-refile-timer))

(defun org-dropbox-version ()
  "Tell the version"
  (interactive)
  (message org-dropbox-version))

(provide 'org-dropbox)

;;; org-dropbox.el ends here
