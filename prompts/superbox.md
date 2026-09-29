use the openspec explore skill

# Superbox - My home for the claude-agent

## Ausgangssituation

Freunde Dich mit Deinem Freund devbox an. Im selben Projekt gibt es einen thread devbox. Frage ihn, er weiß mehr.

## Aufgabenstellung

Es soll ein k8s-debian (latest stable)-deployment in dem claude-cli im yolo-mode starten kann.

Dieses Deployment nennen wir superbox. Die superbox soll die devbox verwenden, um Anwendungen zu erstellen. Ich logge mich mit `kubectl exec ...` in die superbox ein und starte dort claude aktiviere remote-control. Danach arbeite ich mit der claude-app, um die Aufgaben zu prompten. Ich führe dann mit `kubectl exec ...` ein claude-login aus, um die credentials für die superbox zu erhalten. Deine Aufgabe ist es zu planen, wie wir diese Superbox erstellen und wie die Superbox mit den devbox(en) kommuniziert. Außerdem möchte ich tmux installiert haben, um mehrere Sessions auf der Superbox laufen zu lassen.

Verwende k8s-secrets für credentials und andere vertrauliche Informationen. 

Deine Aufgabe ist es diese Superbox mit mir zu planen und anschließend den opensepec-propose-skill zu verwenden, um anschließend mit openspec-apply diese Superbox auf meine Cloud zu deployen





























