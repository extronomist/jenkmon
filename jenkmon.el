;;; jenkmon.el --- Jenkins (Hudson) Monitor for GNU Emacs

;; Copyright (C) 2011  extro

;; Author: extro <extronomist@googlemail.com>
;; Version: 1.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.



(provide 'jenkmon)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; USAGE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; add the following to your .emacs:
;; (add-to-list 'load-path "~/.emacs/")
;; (require 'jenkmon)
;; 
;; add configuration: 
;; (setq jenkmon-superviser-list 
;;       '(("ci-server01" "pattern01")
;;         ("ci-server02" "pattern02")))
;; 
;; note: the pattern is considered a elisp regex
;; 
;; start/stop:
;; use jenkmon-start / jenkmon-stop
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;; variable for the timer object
(defvar jenkmon-timer nil)
(defvar jenkmon-buffer nil)
(defvar jenkmon-buffer-name "jenkins-monitor")



;; start function
(defun jenkmon-start ()
  (interactive)

  (when (timerp jenkmon-timer)
    (cancel-timer jenkmon-timer))
  ; create the new buffer and switch to it
  (setq jenkmon-buffer (generate-new-buffer jenkmon-buffer-name))
  (switch-to-buffer jenkmon-buffer)

  ;; switch on org-mode
  (org-mode)
  ;; setting background and foreground
  (set-background-color "#151530")
  (set-foreground-color "DarkSlateGray1")


  ;;; definig some custome fonts
  ;;; check colors with M-x list-color-display
  (defface font-lock-jenkmon-blue-face
    '((((class color) (background light)) (:bold t :foreground "green")))
    "K3 log file font")
  (defvar font-lock-jenkmon-blue-face 'font-lock-jenkmon-blue-face
    "K3 log file font")

  ;; (defface font-lock-jenkmon-server-face
  ;;   '((((class color) (background light)) (:bold t :background "#ff7f00")))
  ;;   "jenkmon server font")
  ;; (defvar font-lock-jenkmon-server-face 'font-lock-jenkmon-server-face
  ;;   "jenkmon server font")


  ; set syntax highlighting
  (font-lock-mode 1);; does seem to help here!
  ;;(font-lock-add-keywords nil
  (font-lock-add-keywords 'org-mode
     '(("\\<\\(red\\)" 1 font-lock-warning-face prepend)
       ;;("\\<\\(blue\\)" 1 font-lock-jenkmon-blue-face prepend)
       ("\\<\\(blue\\)" 1 font-lock-warning-face prepend)
       ;;("\\<\\(BUILDING\\)" 1 font-lock-preprocessor-face prepend)
       ;;("\\<\\(blue\\)" 1 font-lock-type-face prepend)
       ;;("\\(|.*|\\)" 1 font-lock-jenkmon-server-face prepend)
       ;;("\\(|.*|\\)" 1 font-lock-jenkmon-blue-face prepend)
       ;;("\\<\\(blue\\)" 1 font-lock-jenkmon-blue-face prepend)
       ;;("\\(blue\\)" 1 font-lock-jenkmon-blue-face prepend)
       ;;("\\<\\(UNSTABLE\\)" 1 font-lock-function-name-face prepend)
       ))

  ; initialize the timer
  (setq jenkmon-timer
	;(run-with-idle-timer 1 1 #'jenkmon-callback (current-buffer)))
	; using run-at-time here this updates the buffer also!
	; start after X second when started, first parameter
	; update every Y second specified by the second parameter
	; callback function to be called third parameter
	(run-at-time 1 jenkmon-update-interval #'jenkmon-callback)) 
)

;; stop function
(defun jenkmon-stop () 
  (interactive)
  (when (timerp jenkmon-timer)
    (cancel-timer jenkmon-timer))
  (setq jenkmon-timer nil)
  (kill-buffer jenkmon-buffer)
)

;; callback function for the timer
(defun jenkmon-callback ()
  (undo-boundary)
  (erase-buffer)
  (insert "==============\n")
  (insert "Jenkins Monitor\n")
  (insert "==============\n\n")
  (insert (concat "Refresh cycle: " (number-to-string jenkmon-update-interval) "sec") "\n\n")
  (insert (format-time-string "%c"))
  (insert "\n")

  (dolist (serverToContact jenkmon-superviser-list)
    (setq serverUrl (car serverToContact))
    (setq jobFilter (car (cdr serverToContact)))

    (setq jobList (jenkmon-filter-job-xml-list jobFilter
		      (jenkmon-fetch-jobs-as-xml 
		       (concat serverUrl "/api/xml?tree=jobs[name]"))))

    (setq jobListFull (mapcar (lambda (x) 
	      (get-job-xml serverUrl  (car (xml-node-children (car (xml-get-children x 'name)))))
	    ) jobList))

    (jenkmon-draw-jobs-xml serverUrl jobListFull)
  ); dolist
  (org-table-align)
  (insert "\n")

  (undo-boundary) ;; this is suggested to do at the end
)



;; input: jenkins url
;;         e.g.: http://ci.jenkins-ci.org
;; output: xml of job list
;;         e.g.: <hudson><job><name>job1</name><job><name>job2</name></job></hudson>
;; TODO rename because this is a generic url to xml fetcher
(defun jenkmon-fetch-jobs-as-xml (ciServerUrl)
;;  (interactive)
  ;; url to be used to get all job names:
  ;; http://jenkins/api/xml?tree=jobs[name]
  ;; see https://wiki.jenkins-ci.org/display/JENKINS/Remote+access+API

  (setq xmlBuffer 
	(url-retrieve-synchronously ciServerUrl))
	 ;;(concat ciServerUrl "/api/xml?tree=jobs[name]")))
  (with-temp-buffer 
    (insert-buffer-substring xmlBuffer)
    (goto-char (point-min))
    (re-search-forward "\\(^\n\\)")
    (copy-region-as-kill (point)(point-max))

    (car kill-ring-yank-pointer) ;; return
  )
)

;; input: xml formatted job list like:
;;        <hudson><job><name>job1</name></job><job><name>job2</name></job></hudson>
;; output: list of job names 
;;        "job1" "job2"
(defun convert-job-xml-to-list (jobListXml)
;;  (interactive)
  
  (setq max-specpdl-size 5)  ; default is 1000, reduce the backtrace level
  (setq debug-on-error t)    ; now you should get a backtrace

  (setq root (with-temp-buffer
	       (insert jobListXml)
	       (xml-parse-region (point-min) (point-max))))
  (setq hudson (car root))
  (setq jobs (xml-get-children hudson 'job))

  (setq jobList nil)
  (dolist (job jobs)
    (setq jobName (car (xml-get-children job 'name)))
    (setq text (car (xml-node-children jobName)))
    (setq jobList (cons text jobList))
    )
  (reverse jobList)
)


;; input: xml formatted jobs status:
;;        <freeStyleProject><name>jenkins_main_trunk</name><color>blue_anime</color></freeStyleProject>
;;        e.g. jenkins api xml url: http://ci.jenkins-ci.org/view/Jenkins%20core/job/jenkins_main_trunk/api/xml?tree=name,color
;; output: list wir the first element beeing the jobname, second job status
;;         ("job1" "blue_anime")
(defun convert-job-status-xml-to-list (jobStatusXml)
;;  (interactive)
  (setq root (with-temp-buffer
	       (insert jobStatusXml)
	       (xml-parse-region (point-min) (point-max))))
  (setq job (car root))
  (setq jobName (car (xml-node-children (car (xml-get-children job 'name)))))
  (setq jobStatus (car (xml-node-children (car (xml-get-children job 'color)))))
  (list jobName jobStatus)
)

;; input: job name
;; output: xml strucutre
;;         e.g.: <freeStyleProject>
;;                 <name>jenkins_main_trunk</name>
;;                 <color>blue</color>
;;               </freeStyleProject>
(defun get-job-xml(ciServerUrl jobName)
;;  (interactive)
  ;; url to get job infos:
  ;; http://ci.jenkins-ci.org/job/jenkins_main_trunk/api/xml?tree=name,color

  (jenkmon-fetch-jobs-as-xml 
   (concat ciServerUrl "/job/" (replace-regexp-in-string " " "%20" jobName) "/api/xml?tree=name,color,inQueue,url"))
)


;; input: cond as regex e.g. job1 , jenkins job list as xml
;;        e.g.: <hudson><job><name>job1</name></job><job><name>job2</name></job></hudson>
;; output: filtered output
;;        e.g.: ((job nil (name nil "job1")))
(defun jenkmon-filter-job-xml-list(condfilter jobXmlList)
;;  (interactive)
  (setq root (with-temp-buffer
	       (insert jobXmlList)
	       (xml-parse-region (point-min) (point-max))))
  (setq jenkmon (car root))
  (setq jobs (xml-get-children jenkmon 'job))

  (delq nil (mapcar (lambda (x) 
	    (if (string-match condfilter (car (xml-node-children (car (xml-get-children x 'name)))))
		x
	        'nil
	    )
	  )
	  jobs))
)

;; input: the job list like:
;;        cond = ".*1" (regex)
;;        lst = "job1" "job2"
;; output: filtered job list
;;         "job1"
(defun filter-job-list (condfilter lst)
;;  (interactive)
  ;; iterated through the job list and check if condition is matched if not return nil which is
  ;; afterwards removed from the list
  (delq nil (mapcar (lambda (x) (if (string-match condfilter x) x 'nil )) lst ))
)

;; input: list of jobs with xml strings
;; ("<freeStyleProject><name>jenkins_main_trunk</name><url></url><color>blue</color><inQueue>false</inQueue></freeStyleProject>"
;;  "<freeStyleProject><name>jenkins_branch_trunk</name><url></url><color>blue</color><inQueue>false</inQueue></freeStyleProject>")
;; also check: http://ci.jenkins-ci.org/job/jenkins_main_trunk/api/xml?tree=name,color,inQueue,url
;;
;; output: generates a org-mode table
(defun jenkmon-draw-jobs-xml (serverUrl jobXmlList)
;;  (interactive)
  (insert "\n\n")
  (insert (concat "|[[" serverUrl "][" (replace-regexp-in-string "http.*//" "" serverUrl) "]] | *status* | *queue* |\n"))
  (insert "|--+--------+-------|\n")

  (dolist (jobXml jobXmlList)
    (setq root (with-temp-buffer
		 (insert jobXml)
		 (xml-parse-region (point-min) (point-max))))
    (setq job (car root))
    (setq jobName (car (xml-node-children (car (xml-get-children job 'name)))))
    (setq jobUrl (car (xml-node-children (car (xml-get-children job 'url)))))
    (setq jobStatus (car (xml-node-children (car (xml-get-children job 'color)))))
    (setq jobQueue (car (xml-node-children (car (xml-get-children job 'inQueue)))))
    (insert (concat "|[[" jobUrl "][" jobName "]]|" jobStatus "|" jobQueue "|\n"))
  )
;;  (org-table-align)
)

;; input: vector 
(defun jenkmon-draw-jobs (serverTitle serverJobStatusVec)
  ;(print serverJobStatusVec)
  (insert (concat "\n| " serverTitle " |\n"))
  (setq i 0)
  (while (< i (length serverJobStatusVec))
    (insert (concat "[" (car (cdr (elt serverJobStatusVec i))) "]" "-> " (car (elt serverJobStatusVec i)) "\n" ))
    (setq i (1+ i))  )
)


(defun jenkmon-testsuite()
;;  (interactive)

  ;; test check if xml is converted to list
  (setq testcase "test_convert: ")
  (if (equal '("job1" "job2") (convert-job-xml-to-list "<hudson><job><name>job1</name></job><job><name>job2</name></job></hudson>"))
      (setq testcase (concat testcase "[pass]"))
      (setq testcase (concat testcase "[fail]"))
  )
  (print testcase)

  ;; test job status convert
  (setq testcase "test_convert-job-status: ")
  (if (equal '("job1" "green") (convert-job-status-xml-to-list "<freeStyleProject><name>job1</name><color>green</color></freeStyleProject>"))
      (setq testcase (concat testcase "[pass]"))
      (setq testcase (concat testcase "[fail]"))
  )
  (print testcase)

  ;; test if filter is working correctly
  (setq testcase "test_filter: ")
  (if (equal '("job2") (filter-job-list "2" '("job1" "job2" "job3")))
      (setq testcase (concat testcase "[pass]"))
      (setq testcase (concat testcase "[fail]"))
  )
  (print testcase)

  ;; test if filter is working correctly
  (setq testcase "test_xmlfilter: ")
  (if (equal '((job nil (name nil "job1"))) (jenkmon-filter-job-xml-list "job1" "<hudson><job><name>job1</name></job><job><name>job2</name></job></hudson>"))
      (setq testcase (concat testcase "[pass]"))
      (setq testcase (concat testcase "[fail]"))
  )
  (print testcase)

)

