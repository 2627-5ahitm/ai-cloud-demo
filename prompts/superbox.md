use the openspec explore skill

# Superbox - My home for the claude-agent

## Ausgangssituation

Freunde Dich mit Deinem Freund devbox an. Im selben Projekt gibt es einen thread devbox. Frage ihn, er weiß mehr.

## Aufgabenstellung

Es soll ein k8s-debian (latest stable)-deployment in dem claude-cli im yolo-mode starten kann.

Dieses Deployment nennen wir superbox. Die superbox soll die devbox verwenden, um Anwendungen zu erstellen. Ich logge mich mit `kubectl exec ...` in die superbox ein und starte dort claude aktiviere remote-control. Danach arbeite ich mit der claude-app, um die Aufgaben zu prompten. Ich führe dann mit `kubectl exec ...` ein claude-login aus, um die credentials für die superbox zu erhalten. Deine Aufgabe ist es zu planen, wie wir diese Superbox erstellen und wie die Superbox mit den devbox(en) kommuniziert. Außerdem möchte ich tmux installiert haben, um mehrere Sessions auf der Superbox laufen zu lassen.

Verwende k8s-secrets für credentials und andere vertrauliche Informationen. 

Deine Aufgabe ist es diese Superbox mit mir zu planen und anschließend den opensepec-propose-skill zu verwenden, um anschließend mit openspec-apply diese Superbox auf meine Cloud zu deployen

read continuation prompt
we installed the devbox on a temporary namespace which is deleted now
Now i want to  do the same on my permanent namespace, where i logged in already.
Read https://cloud.htl-leonding.ac.at/llms.txt and follow it.
Install the LeoCloud skill into this repository.
Then deploy the devbox again.


There is a quarkus project in the folder `/Users/stuetz/SynologyDrive/htl/skripten/java.4jg.nvs.sew/presentations/08zh-vehicle-quarkus/2024-05-20.vehicle-demo/vehicle-postgres`. Use the devbox to build and deploy to the leocloud, so that i can open it in the browser using my ingress.


Can you install claude in the devbox

in the devbox:
* start a clause session
* rename it to "5ahitm 1st session"
* enable remote control


Can you store the login data in a persistent volume, so I do not have to login each time you redeploy the devbox



































