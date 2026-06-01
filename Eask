; -*- lexical-binding: t -*-

(package "package-tutor"
; x-release-please-start-version
         "0.1.1"
; x-release-please-end
         "Auto-generate an org tutorial for any package")

(website-url "https://github.com/chiply/package-tutor")
(keywords "help" "docs" "convenience")

(package-file "package-tutor.el")
(files "*.el")

(script "test" "eask test ert test/package-tutor-test.el")

(source "gnu")
(source "melpa")

(depends-on "emacs" "29.1")

(development
 (depends-on "package-lint")
 (depends-on "elisp-lint")
 (depends-on "relint"))
