# Marquer les rendus générés par IA — métadonnées IPTC et XMP, bandeau visible au choix

Code de la démonstration du module 4 de la série « Clic par clic » **Créer un service d'IA
compatible agentique : le studio 3D**.

Vidéo : {{video}}

## But

Une image sortie du studio ressemble à une photo de produit. Ce dépôt apprend au studio du
module 3 à **marquer chaque rendu comme généré par intelligence artificielle**, à deux niveaux :

- **invisible, toujours** : dans le fichier PNG, un paquet XMP avec le type de source IPTC
  `trainedAlgorithmicMedia` (« créé par IA générative »), la date de création, le générateur
  « AI studio3D » et l'identifiant unique de la demande, plus des champs texte PNG (`Software`,
  `Creation Time`, `Source`, `Disclaimer`) ; dans le modèle 3D (GLB), le champ `asset.generator`
  et les mêmes informations dans `asset.extras` ;
- **visible, au choix** : un bandeau **toujours identique** en bas à droite de l'image
  (`AI studio3D · AAAA-MM-JJ`, date UTC de fin du rendu), demandé par l'utilisateur (le modèle
  passe `marquage_visible: true` à l'outil MCP) ou imposé par l'organisation.

Le marquage est fait par le **worker, après Blender**, avant que les fichiers ne soient rangés :
le code de la scène, écrit par le modèle, ne peut ni l'éviter ni le modifier. Une erreur de
marquage met la demande en erreur : aucun fichier non marqué ne sort.

## Contenu

| Fichier | Rôle |
|---|---|
| `studio/marquage.py` | **Nouveau.** Paquet XMP, champs texte PNG (Pillow), bandeau visible (police DejaVu Sans 22 px, noir à 60 %, marge de 16 px), réécriture du bloc JSON du GLB |
| `studio/api.py` | Serveur MCP du module 3, plus : paramètre facultatif `marquage_visible` de `soumettre_rendu` (et sa description pour le modèle), politique de l'organisation, identifiant unique (UUID) de chaque demande ; `etat_rendu` et `mes_rendus` renvoient le choix effectif |
| `studio/travailleur.py` | Worker du module 3, plus : appel du marquage juste après Blender, avant l'écriture dans Redis |
| `studio/commun.py` | Politique lue dans l'environnement (`MARQUAGE_VISIBLE_DEFAUT`, `MARQUAGE_VISIBLE_IMPOSE`), nouveaux champs de la demande |
| `studio/rendu.py`, `studio/metriques.py` | Inchangés depuis le module 3 |
| `studio/Dockerfile` | Image `studio3d:3` : celle du module 3, plus Pillow 12.3.0 et la police DejaVu Sans (`fonts-dejavu-core`) |
| `k8s-echelle.yaml` | Manifeste du module 3, plus les deux variables de la politique sur `studio-api` (`"non"` par défaut) |
| `lire_marquage.py` | Lecture du marquage d'un PNG ou d'un GLB, bibliothèque standard seulement (ExifTool ne lit pas le glTF) |
| `essai/rendu-marque.sh` | Deux rendus (sans puis avec bandeau), téléchargement par les liens signés, affichage du marquage |
| `open-webui/` | En-tête d'identité de la connexion MCP et prompt système du modèle « Studio 3D », complété d'une phrase sur la mention visible |
| `.env.example` | Variables à renseigner (jeton, mot de passe Redis), sans valeur |

## Prérequis

- Le studio à l'échelle du **module 3** (dépôt
  [`clic-par-clic-studio3d-03-grafana`](https://github.com/guilhem-/clic-par-clic-studio3d-03-grafana)) :
  Redis, KEDA 2.21, secret `studio`, connexion et modèle « Studio 3D » dans Open WebUI.
  L'observabilité du module 3 n'est pas nécessaire.
- Docker, `kubectl` et un cluster Kubernetes (la vidéo utilise **k3d**, cluster `tterm`, Traefik
  publié sur le port 8080 de la machine).
- Sur le poste : [ExifTool](https://exiftool.org/) 13.x (Windows : `winget install OliverBetz.ExifTool`)
  et Python 3.10 ou plus pour `lire_marquage.py`.

## Installation pas à pas

1. **Image** du studio, avec le marquage :

   ```bash
   docker build -t studio3d:3 studio
   k3d image import studio3d:3 -c tterm      # k3d ; sinon, poussez l'image dans votre registre
   ```

2. **Politique de l'organisation.** Dans `k8s-echelle.yaml`, sur `studio-api` :

   | Variable | `"non"` (défaut) | `"oui"` |
   |---|---|---|
   | `MARQUAGE_VISIBLE_DEFAUT` | pas de bandeau si l'utilisateur ne demande rien | bandeau si l'utilisateur ne précise rien |
   | `MARQUAGE_VISIBLE_IMPOSE` | l'utilisateur choisit | bandeau toujours, quoi que demande l'utilisateur |

   Le marquage invisible ne se désactive pas.

3. **Studio** :

   ```bash
   kubectl apply -f k8s-echelle.yaml
   kubectl -n studio3d rollout restart deployment/studio-api
   kubectl -n studio3d rollout status deployment/studio-api
   ```

4. **Open WebUI** : dans le modèle « Studio 3D », remplacez le prompt système par celui de
   `open-webui/consignes-modele.txt` (une phrase ajoutée : `marquage_visible` à `true` seulement si
   l'utilisateur demande une mention visible). Rafraîchissez la connexion MCP pour que le nouveau
   paramètre de l'outil soit lu.

5. **Essai.** Dans Open WebUI : « Crée une lampe de bureau jaune, posée sur un bureau en bois. »,
   puis « Refais la même lampe, avec la mention visible. », puis « Où en sont mes rendus ? ».
   Ou, sans Open WebUI, avec un accès local et le jeton :

   ```bash
   kubectl -n studio3d port-forward svc/studio 8000:8000 &
   export STUDIO_JETON=…          # celui du secret « studio »
   ./essai/rendu-marque.sh        # sous Windows (Git Bash) : PYTHON=python ./essai/rendu-marque.sh
   ```

6. **Lire le marquage** d'un fichier téléchargé :

   ```bash
   exiftool -G1 -s -XMP:all -PNG:all rendu.png
   python lire_marquage.py rendu.png
   python lire_marquage.py modele.glb
   ```

## Points à connaître

- **Où marquer ?** Jamais dans le code de la scène : il est écrit par le modèle, qui pourrait
  l'oublier ou le modifier. Le worker marque après la sortie de Blender, dans son propre processus.
- **Type de source.** L'IPTC distingue `trainedAlgorithmicMedia` (créé par IA générative) et
  `algorithmicMedia` (algorithme pur, sans données d'entraînement). Ici, la scène est composée par
  un modèle de langage puis calculée par Blender : on retient `trainedAlgorithmicMedia`, choix
  prudent puisque le contenu est décidé par un modèle entraîné.
- **Un bandeau toujours identique** : même police, même taille, même place ; seule la date change.
  Un bandeau qui varie, personne ne le reconnaît.
- **Le numéro et l'identifiant** : le numéro de la demande sert aux humains, l'UUID
  (`xmpMM:DocumentID`, `urn:uuid:…`) à la traçabilité.
- **Limites** : une capture d'écran, ou un réseau social qui recompresse l'image, efface les
  métadonnées ; un bandeau se recadre. Couches suivantes possibles : un filigrane invisible dans
  les pixels (par exemple TrustMark, à code ouvert), et une signature C2PA, qui demande une clé
  privée et un certificat reconnu (avec un certificat auto-signé, les outils de vérification
  l'affichent comme inconnue) : un chantier à part, non traité ici. Le vocabulaire IPTC utilisé ici
  est celui des actions C2PA : passer à C2PA plus tard ne change pas les informations, seulement
  leur garantie.

## Ce que disent les textes (sans conseil juridique)

Repères vérifiés en octobre 2026, **à vérifier avec vos juristes** :

- Union européenne : règlement (UE) 2024/1689 sur l'intelligence artificielle, article 50 :
  les fournisseurs de systèmes qui génèrent des images marquent leurs sorties dans un format
  lisible par machine et détectable (paragraphe 2) ; les hypertrucages sont signalés par qui les
  diffuse (paragraphe 4). Obligations applicables depuis le 2 août 2026 ; selon le règlement
  « omnibus numérique » sur l'IA, les systèmes déjà en service à cette date avaient jusqu'au
  2 décembre 2026 pour le marquage. Un code de bonnes pratiques européen (juin 2026) recommande
  plusieurs couches de marquage.
- Chine : mesures d'étiquetage des contenus générés par IA (en vigueur depuis septembre 2025) :
  mention visible et marquage dans le fichier.
- Californie : AI Transparency Act (SB 942, modifié par AB 853) : marquage dans le fichier,
  mention visible au choix de l'utilisateur.

Une organisation qui met en service son propre studio peut être considérée comme fournisseur.

## Suite de la série

- Module précédent : **Observer le studio avec Grafana** — dépôt
  [`clic-par-clic-studio3d-03-grafana`](https://github.com/guilhem-/clic-par-clic-studio3d-03-grafana).
- Module suivant : **Une bibliothèque d'assets pour tous les rendus** (à venir).

## Licence

MIT, voir [`LICENSE`](LICENSE). Blender est distribué sous licence GPL par la Blender Foundation ;
Redis, KEDA, Pillow et ExifTool sont des projets indépendants. Cette série est indépendante des
éditeurs des logiciels présentés.
