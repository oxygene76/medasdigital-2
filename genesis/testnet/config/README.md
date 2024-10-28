### Schritt-für-Schritt Anleitung zur Erstellung der Validatoren für das MedasDigital-Testnetz

Diese Anleitung beschreibt die Schritte, um die **Validatoren** für das Testnetz der MedasDigital-Chain korrekt einzurichten und die `gentx`-Transaktionen in die Genesis-Datei zu integrieren.

#### 1. Erstellung der Validator-Schlüsselpaare
1.1. Auf jedem Node, der Validator werden soll, erstelle ein Schüsselpaar:
```bash
medasdigitald keys add <validator-name> --keyring-backend test
```
- **`<validator-name>`**: Wähle einen Namen für den Validator.

1.2. Notiere die generierte **Adresse** für den Validator-Schlüssel.

#### 2. Erstellung der `gentx`-Transaktionen
2.1. Erstelle eine **`gentx`-Transaktion** für jeden Validator:
```bash
medasdigitald gentx <validator-name> 1000000000umedastest --chain-id medasdigital-test-2 --moniker "<validator-moniker>"
```
- **`<validator-name>`**: Der Name des Validators, der im vorherigen Schritt verwendet wurde.
- **`<validator-moniker>`**: Öffentlich sichtbarer Name des Validators.

2.2. Die `gentx`-Datei wird im Verzeichnis **`~/.medasdigitald/config/gentx/`** erstellt.

#### 3. Sammlung der `gentx`-Transaktionen
3.1. Sammle alle **`gentx`-Dateien** von allen Nodes und kopiere sie in den **`gentxs`-Ordner** der Genesis-Datei:
```bash
cp ~/.medasdigitald/config/gentx/*.json ~/.medasdigitald/config/gentxs/
```

#### 4. Integration der `gentx`-Transaktionen in die Genesis-Datei
4.1. Füge alle `gentx`-Transaktionen in die Genesis-Datei ein:
```bash
medasdigitald collect-gentxs
```
- Dieser Befehl integriert die `gentx`-Transaktionen und aktualisiert die **Genesis-Datei** entsprechend.

#### 5. Validierung der Genesis-Datei
5.1. Validieren Sie die aktualisierte Genesis-Datei:
```bash
medasdigitald validate-genesis
```
- Dieser Schritt stellt sicher, dass die Genesis-Datei fehlerfrei ist.

#### 6. Start des Testnetzes
6.1. Sobald die Genesis-Datei erfolgreich validiert wurde, kann das Testnetz gestartet werden:
```bash
medasdigitald start
```

---
Mit dieser Anleitung kannst du die Validatoren korrekt erstellen und das MedasDigital-Testnetz erfolgreich starten. Sollte es Fragen oder Probleme geben, stehe ich dir gerne zur Verfügung.

