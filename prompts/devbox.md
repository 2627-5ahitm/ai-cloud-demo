# Devbox - Entwicklungsumgebung für agentisches Programmieren in der Cloud

## Preface

Das Ziel ist es eine Entwicklungsumgebung einzurichten, um Programme zu kompilieren, testen, deployen usw, die nicht auf meinem Laptop läuft

## Istzustand

An der HTL Leonding gibt es eine eigene Cloud mit der Technologie kubernetes, die es ermöglicht, Container zu starten und zu verwalten. Diese Cloud kann genutzt werden, um Entwicklungsumgebungen für verschiedene Programmiersprachen und Frameworks bereitzustellen.


## Aufgabenstellung

Deine aufgabe ist es ein Deployment zu erstellen, sodass ich eine DevBox habe, die meine Projekt erstellen kann.

Folgende Entwicklungsumgebungen sollten installiert sein:

| Programmiersprache | Framework |
|--------------------|-----------|
| JavaScript         | Node.js   |
| Java               | Quarkus   |

Tools
- Playwright 
- httpyac
- curl

OS
- Debian latest stable

Deine Aufgabe ist es ein Deployment zu erstellen, das diese Entwicklungsumgebung in meine kubernetes cloud deployed. Diese k8s-Umgebung wird später von einem ki-Agenten benutzt, um meine Anwendung zu erstellen, zu testen und zu deployen. Kommuniziert wird mit `kubectl exec ...` und `kubectl cp ...`. Du bist bereits in meinem aktuellen Namespace.

## Testing

Erstelle eine Quarkus Demo Applikation und kompiliere und teste diese mit httpyac. Danach erstelle eine Node.js Applikation, die auf das Quarkus Backend zugreift und teste diese ebenfalls.


## Vorgangsweise

Verwende Subagenten mit einem billigeren Model, um die Aufgaben zu erledigen. 









https://cloud.htl-leonding.ac.at