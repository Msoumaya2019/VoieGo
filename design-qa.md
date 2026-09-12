# Design QA — VoieGo Flutter

Date : 2026-09-12

## Cible et capture

- Cible : option 3 choisie par l’utilisateur, écran mobile VoieGo Transilien L.
- Implémentation : build Flutter Web release, viewport mobile de 430 px dans le navigateur intégré.
- État comparé : Transilien, ligne L, prochain passage vers Versailles Rive Droite, données de démonstration.
- Comparaison : référence et implémentation capturées côte à côte au même état.

## Résultats

- P0 : aucun.
- P1 : aucun.
- P2 : aucun.
- P3 : la maquette de référence compacte tout le parcours sur un écran très haut ; l’application conserve un défilement vertical afin de préserver des cibles tactiles accessibles et un texte lisible sur les petits iPhone.

## Vérifications fonctionnelles

- Les quatre réseaux sont sélectionnables.
- Les lignes changent selon le réseau.
- Le changement de direction met à jour destination et attente.
- Le suivi du passage change d’état et affiche une confirmation.
- La carte et le détail trafic s’ouvrent dans des feuilles modales.
- Aucun avertissement ni erreur n’est présent dans la console du build de contrôle.

final result: passed
