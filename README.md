Jenkmon
=======

Jenkins (Hudson) Monitor for GNU Emacs


Usage
-----

add the following to your .emacs:

    (add-to-list 'load-path "~/.emacs/")
    (require 'jenkmon)
 
add configuration to your .emacs: 

    ;; jenkmon ci server/pattern list
    (setq jenkmon-superviser-list 
      '(("ci-server01" "pattern01")
         ("ci-server02" "pattern02")))
    ;; specify the upate interval in sec (here 60 seconds)
    (setq jenkmon-update-interval 60)

 
note: the pattern is considered as a elisp regex

To start / stop the monitor use the following commands (M-x):

   jenkmon-start / jenkmon-stop


Infos
-----
Jenkmon uses the Jenkins remote api to get the necessary information.
The remote api is described here [Jenkins Remote API](https://wiki.jenkins-ci.org/display/JENKINS/Remote+access+API).
Further more [org-mode](http://orgmode.org) is used to display job infos (ci-server and jobs are displayed as urls).


    ==============
    Jenkins Monitor
    ==============

    Refresh cycle: 10sec

    Sat 30 Apr 2011 08:01:24 PM CEST


    | ci-server.org | *status* | *queue* |
    |---------------+----------+---------|
    | job1          | yellow   | false   |
    | job2          | blue     | false   |


Have fun