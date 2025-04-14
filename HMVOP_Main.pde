import gab.opencv.*;
import java.awt.*;
import processing.video.*;
import java.util.ArrayList;
import java.awt.Robot;
import java.awt.event.InputEvent;

Capture video;
OpenCV opencv;
Robot robot;

PVector handPosition = new PVector(0, 0);
PVector prevHandPosition = new PVector(0, 0);
float smoothingFactor = 0.6; // Reduced for smoother movement
float maxMovementPerFrame = 30.0; // Maximum allowed movement per frame

boolean isClicking = false;
int lastClickTime = 0;
float clickThreshold = 50.0;
int clickCooldownTime = 500;

ArrayList<Float> frameRates = new ArrayList<Float>();
int maxFramesToTrack = 30;
int startTime;
int frameCount = 0;

// Settings
boolean showVideo = true; // Toggle to show/hide video feed
boolean controlMouse = false; // Toggle to control actual mouse cursor

// Variables globales à ajouter :
PVector indexTip = new PVector();
PVector prevIndexTip = new PVector();
boolean clickReady = false;
boolean indexUp = false;
// configuraiton test
boolean testMode = false;
int testStartTime = 0;
int testDuration = 5000; // Durée du test (ms) : 5 secondes
PVector testStartClick = null;
PVector testStartColor = null;



void setup() {
  size(1280, 720);
  video = new Capture(this, 640, 480);
  video.start();
  opencv = new OpenCV(this, 640, 480);
  startTime = millis();
  noCursor();
  frameRate(30);
  // Initialize robot for mouse control
  try {
    robot = new Robot();
  } catch (Exception e) {
    println("Could not initialize Robot: " + e.getMessage());
  }
  

}

void draw() {
  background(0);
  
  frameRates.add(frameRate);
  if (frameRates.size() > maxFramesToTrack) {
    frameRates.remove(0);
  }

  if (video.available()) {
    video.read();
    
    // Only display video if showVideo is true
    if (showVideo) {
      pushMatrix();
      scale(-1, 1);
      image(video, -width/2, 0, width/2, height/2);
      popMatrix();
    }
    
    // Skin detection and hand tracking
    PImage skinMask = createSkinMask();
    
    // Load the skin mask into OpenCV for contour detection
    opencv.loadImage(skinMask);
    
    // Contour detection
    ArrayList<Contour> contours = opencv.findContours();

    if (contours.size() > 0) {
      Contour handContour = findLargestContour(contours);

      if (handContour != null) {
        Rectangle r = handContour.getBoundingBox();
        PVector currentHand = new PVector(r.x + r.width/2, r.y + r.height/2);
        
        // Check if the movement is too large (potential tracking error)
        float distance = PVector.dist(currentHand, handPosition);
        if (distance > maxMovementPerFrame && frameCount > 10) {
          // If movement is too large, move only partially towards the new position
          PVector direction = PVector.sub(currentHand, handPosition);
          direction.normalize();
          direction.mult(maxMovementPerFrame);
          currentHand = PVector.add(handPosition, direction);
        }

        // Apply smoothing
        handPosition.x = lerp(handPosition.x, currentHand.x, smoothingFactor);
        handPosition.y = lerp(handPosition.y, currentHand.y, smoothingFactor);

        // Only display contour if showVideo is true
        if (showVideo) {
          pushMatrix();
          scale(-1, 1);
          translate(-width/2, 0);
          noFill();
          stroke(0, 255, 0);
          handContour.draw();
          
          fill(255, 0, 0);
          ellipse(handPosition.x, handPosition.y, 10, 10);
          popMatrix();
          image(skinMask, width/2, 0, width/2, height/2);                  
          image(createPinkMask(1), width/2, height/2, width/2, height/2);
          stroke(255);
          noFill();
          rect(width/2, height/2, width/2, height/2);
        }

        // Map hand position to screen coordinates
        float mappedX = map(handPosition.x, 0, 640, width, 0);
        float mappedY = map(handPosition.y, 0, 480, 0, height);

        // Draw cursor on screen
        fill(255, 200);
        ellipse(mappedX, mappedY, 15, 15);
        
        // Control actual mouse if enabled
        if (controlMouse && robot != null) {
          // Map hand position to entire screen coordinates
          int screenX = (int)map(handPosition.x, 0, 640, displayWidth, 0);
          int screenY = (int)map(handPosition.y, 0, 480, 0, displayHeight);
          
          // Restrict to screen bounds
          screenX = constrain(screenX, 0, displayWidth);
          screenY = constrain(screenY, 0, displayHeight);
          
          // Move mouse cursor
          robot.mouseMove(screenX, screenY);
        }

        // Detect and handle clicks
        boolean wasClicking = isClicking;
        detectClicks(handContour);
        
        // Perform actual mouse click if controlling mouse
        
        
        prevHandPosition = handPosition.copy();
      } else {
        handPosition = prevHandPosition.copy();
      }
    } else {
      handPosition = prevHandPosition.copy();
    }

    displayMetrics();
  }
  // 🎨 Détection couleur indépendante
  PVector colorPoint = detectColorPoint();
  if (colorPoint != null) {
    fill(255, 0, 255);
    noStroke();
    ellipse(colorPoint.x, colorPoint.y, 20, 20);
  }
  frameCount++;
}
PImage createPinkMask(float tolerance) {
  PImage mask = createImage(video.width, video.height, RGB);
  video.loadPixels();
  mask.loadPixels();

  // Teinte cible (rose fluo)
  float targetHue = 225;  // Cible la couleur rose fluo

  // Plages dynamiques autour de la teinte cible
  float hueMin = targetHue - 30 * tolerance;
  float hueMax = targetHue + 30 * tolerance;

  for (int i = 0; i < video.pixels.length; i++) {
    color c = video.pixels[i];

    colorMode(HSB, 255);
    float h = hue(c);  // Récupère la teinte
    colorMode(RGB, 255);

    // Détecte seulement la teinte rose avec un facteur de tolérance
    if (h >= hueMin && h <= hueMax) {
      mask.pixels[i] = color(255);  // Blanc pour détecter le rose
    } else {
      mask.pixels[i] = color(0);    // Noir sinon
    }
  }

  mask.updatePixels();
  return mask;
}





PImage createSkinMask() {
  // Create a new mask image
  PImage finalMask = createImage(video.width, video.height, RGB);
  
  // Hue mask
  opencv.loadImage(video);
  opencv.useColor(HSB);
  opencv.setGray(opencv.getH());
  opencv.inRange(0, 20);
  PImage hueMask = opencv.getOutput().copy();
  
  // Saturation mask
  opencv.loadImage(video);
  opencv.useColor(HSB);
  opencv.setGray(opencv.getS());
  opencv.inRange(50, 255);
  PImage satMask = opencv.getOutput().copy();
  
  // Brightness mask
  opencv.loadImage(video);
  opencv.useColor(HSB);
  opencv.setGray(opencv.getB());
  opencv.inRange(50, 255);
  PImage briMask = opencv.getOutput().copy();
  
  // Manually combine the masks using pixel operations
  hueMask.loadPixels();
  satMask.loadPixels();
  briMask.loadPixels();
  finalMask.loadPixels();
  
  for (int i = 0; i < hueMask.pixels.length; i++) {
    // Check if pixel is white in all three masks (boolean AND)
    if (brightness(hueMask.pixels[i]) > 0 && 
        brightness(satMask.pixels[i]) > 0 && 
        brightness(briMask.pixels[i]) > 0) {
      finalMask.pixels[i] = color(255);
    } else {
      finalMask.pixels[i] = color(0);
    }
  }
  
  finalMask.updatePixels();
  
  // Apply morphological operations to clean up the mask
  opencv.loadImage(finalMask);
  opencv.dilate();
  opencv.dilate();  // Additional dilation for more robust detection
  opencv.erode();
  
  return opencv.getOutput();
}

Contour findLargestContour(ArrayList<Contour> contours) {
  if (contours.isEmpty()) return null;
  
  Contour largest = contours.get(0);
  for (Contour c : contours) {
    if (c.area() > largest.area()) {
      largest = c;
    }
  }
  
  // Increase minimum area to avoid small noise
  if (largest.area() < 3000) return null;
  
  return largest;
}

void detectClicks(Contour handContour) {
  try {
    Contour hullContour = handContour.getConvexHull();
    ArrayList<PVector> hullPoints = hullContour.getPoints();
    if (hullPoints.isEmpty()) return;

    // Calcul du centre de gravité de la main
    PVector centroid = new PVector(0, 0);
    for (PVector p : hullPoints) {
      centroid.add(p);
    }
    centroid.div(hullPoints.size());

    // Filtrage des points trop proches et trop centrés
    float minFingerSeparation = 30;
    float minDistanceFromCenter = 40;

    ArrayList<PVector> fingerCandidates = new ArrayList<PVector>();

    for (PVector p : hullPoints) {
      float dist = PVector.dist(p, centroid);
      if (dist > minDistanceFromCenter) {
        boolean tooClose = false;
        for (PVector existing : fingerCandidates) {
          if (PVector.dist(p, existing) < minFingerSeparation) {
            tooClose = true;
            break;
          }
        }
        if (!tooClose) {
          fingerCandidates.add(p);
        }
      }
    }

    // Tri des doigts de gauche à droite (x croissant)
    fingerCandidates.sort((a, b) -> Float.compare(a.x, b.x));

    if (fingerCandidates.size() > 0) {
      // 👉 Choix dynamique : doigt à l’extrémité gauche (index dans la plupart des cas)
      int targetIndex = 0;
      int chosenIndex = -1;
      
      // On cherche d'abord à l'endroit idéal
      if (fingerCandidates.size() > targetIndex) {
        chosenIndex = targetIndex;
      } else {
        // Sinon on cherche autour de targetIndex
        for (int offset = 1; offset < fingerCandidates.size(); offset++) {
          int tryLeft = targetIndex - offset;
          int tryRight = targetIndex + offset;
      
          if (tryLeft >= 0 && tryLeft < fingerCandidates.size()) {
            chosenIndex = tryLeft;
            break;
          }
          if (tryRight < fingerCandidates.size()) {
            chosenIndex = tryRight;
            break;
          }
        }
      
        // Si aucun index valide n’est trouvé, on prend le doigt le plus à gauche
        if (chosenIndex == -1 && !fingerCandidates.isEmpty()) {
          chosenIndex = 0;
        }
      }

      PVector indexCandidate = fingerCandidates.get(chosenIndex);

      float distanceFromCenter = centroid.y - indexCandidate.y;

      // Seuils de détection
      float liftThreshold = 35;
      float dropThreshold = 30;

      if (indexUp && distanceFromCenter < dropThreshold) {
        if ((millis() - lastClickTime > clickCooldownTime)) {
          println("🖱️ Clic détecté !");
          isClicking = true;
          lastClickTime = millis();
          if (controlMouse && robot != null) {
            robot.mousePress(InputEvent.BUTTON1_DOWN_MASK);
            robot.mouseRelease(InputEvent.BUTTON1_DOWN_MASK);
          }
        }
        indexUp = false;
      }

      if (distanceFromCenter > liftThreshold) {
        indexUp = true;
      }
     
      
      pushMatrix();
      
      // Visualisation
      
      scale(-1, 1);
      translate(-width / 2, 0);
      fill(indexUp ? color(0, 0, 255) : color(0, 255, 0));
      ellipse(indexCandidate.x, indexCandidate.y, 15, 15);

      // Dessine les autres doigts détectés
      noFill();
      stroke(255, 255, 0);
      for (PVector p : fingerCandidates) {
        ellipse(p.x, p.y, 10, 10);
      }

      popMatrix();
    }

  } catch (Exception e) {
    println("Erreur dans detectClicks : " + e.getMessage());
  }
}

PVector detectColorPoint() {
  PVector highestPoint = null;
  int step = 5; // échantillonnage pour perf
 //visualise pink marquer 
  color targetColor = color(255, 0, 255); // Rouge
  float colorThreshold = 80.0;
  PVector colorPoint = null;
  int stepSize = 5; // Pour alléger le traitement
  

  for (int y = 0; y < height; y += step) {
    for (int x = 0; x < width; x += step) {
      color c = get(x, y);
      float d = dist(red(c), green(c), blue(c), red(targetColor), green(targetColor), blue(targetColor));
      if (d < colorThreshold) {
        if (highestPoint == null || y < highestPoint.y) {
          highestPoint = new PVector(x, y);
        }
      }
    }
  }

  return highestPoint;
}





void displayMetrics() {
  fill(255);
  textSize(16);

  float avgFrameRate = 0;
  for (float fr : frameRates) {
    avgFrameRate += fr;
  }
  avgFrameRate /= frameRates.size() > 0 ? frameRates.size() : 1;

  text("Position Main: (" + (int)handPosition.x + ", " + (int)handPosition.y + ")", 20, height - 150);
  text("Position Écran: (" + (int)map(handPosition.x, 0, 640, width, 0) + ", " +
       (int)map(handPosition.y, 0, 480, 0, height) + ")", 20, height - 130);
  text("Frame Rate: " + nf(frameRate, 0, 1) + " fps", 20, height - 110);
  text("FPS Moyen: " + nf(avgFrameRate, 0, 1) + " fps", 20, height - 90);
  text("Clic: " + (isClicking ? "Oui" : "Non"), 20, height - 70);
  text("Temps: " + nf((millis() - startTime) / 1000.0, 0, 1) + " s", 20, height - 50);
  text("Contrôle souris: " + (controlMouse ? "Activé" : "Désactivé"), 20, height - 30);
  text("Affichage vidéo: " + (showVideo ? "Activé" : "Désactivé"), 20, height - 10);

  fill(isClicking ? color(255, 0, 0) : color(0, 255, 0));
  ellipse(width - 50, height - 50, 30, 30);
}

void keyPressed() {
  if (key == ESC) {
    exit();
  } else if (key == 'v' || key == 'V') {
    // Toggle video display
    showVideo = !showVideo;
  } else if (key == 'm' || key == 'M') {
    // Toggle mouse control
    controlMouse = !controlMouse;
  }
   if (key == 't') { // Appuyer sur "t" pour démarrer le test
    println("🧪 Mode test activé : placez votre main sur la souris !");
    testMode = true;
    testStartTime = millis();
  }
}
class Finger {
  String name;
  PVector position;
  String action;

  Finger(String name, PVector pos, String action) {
    this.name = name;
    this.position = pos.copy();
    this.action = action;
  }

  void draw() {
    pushMatrix();
    scale(-1, 1);
    translate(-width / 2, 0);
    fill(action.equals("left_click") ? color(0, 255, 0) :
         action.equals("right_click") ? color(0, 0, 255) :
         color(255, 255, 0));
    ellipse(position.x, position.y, 15, 15);
    fill(255);
    text(name, position.x + 10, position.y);
    popMatrix();
  }

  void triggerAction() {
    if (controlMouse && robot != null) {
      if (action.equals("left_click")) {
        robot.mousePress(InputEvent.BUTTON1_DOWN_MASK);
        robot.mouseRelease(InputEvent.BUTTON1_DOWN_MASK);
        println("Clic gauche (index)");
      } else if (action.equals("right_click")) {
        robot.mousePress(InputEvent.BUTTON3_DOWN_MASK);
        robot.mouseRelease(InputEvent.BUTTON3_DOWN_MASK);
        println("Clic droit (majeur)");
      }
    }
  }
}
