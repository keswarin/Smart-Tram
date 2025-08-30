// index.js (ในโฟลเดอร์ functions)

const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentUpdated, onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onValueWritten} = require("firebase-functions/v2/database");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");
const logger = require("firebase-functions/logger");

admin.initializeApp();
const db = admin.firestore();

const app = express();
app.use(cors({origin: true}));

// --- API Endpoints ---

app.get("/buildings", async (req, res) => {
  try {
    const buildingsSnapshot = await db.collection("pickup_points").where("isActive", "==", true).get();
    const buildings = [];
    buildingsSnapshot.forEach((doc) => {
      const buildingData = doc.data();
      buildings.push({
        id: doc.id,
        name: buildingData.name,
        coordinates: buildingData.coordinates,
      });
    });
    return res.status(200).json(buildings);
  } catch (error) {
    logger.error("Error fetching buildings:", error);
    return res.status(500).send("Something went wrong fetching buildings.");
  }
});

app.post("/requests", async (req, res) => {
  try {
    const {
      userId,
      pickupBuildingId,
      dropoffBuildingId,
      pickupPointName,
      dropoffPointName,
      passengerCount,
    } = req.body;

    if (!userId || !pickupBuildingId || !dropoffBuildingId || !passengerCount) {
      return res.status(400).send("Missing required fields.");
    }

    const newRequest = {
      userId: userId,
      pickupPointId: pickupBuildingId,
      dropoffPointId: dropoffBuildingId,
      pickupPointName: pickupPointName,
      dropoffPointName: dropoffPointName,
      passengerCount: passengerCount,
      driverId: null,
      status: "pending",
      cancellationReason: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const requestRef = await db.collection("ride_requests").add(newRequest);
    return res.status(201).json({id: requestRef.id, message: "Request created successfully"});
  } catch (error) {
    logger.error("Error creating request:", error);
    return res.status(500).send("Something went wrong creating the request.");
  }
});

app.post("/requests/:requestId/cancel", async (req, res) => {
  try {
    const requestId = req.params.requestId;
    const requestRef = db.collection("ride_requests").doc(requestId);
    const requestDoc = await requestRef.get();

    if (!requestDoc.exists) {
      return res.status(404).send("Request not found.");
    }
    if (requestDoc.data().status !== "pending") {
      return res.status(400).send("This request can no longer be cancelled.");
    }
    await requestRef.delete();
    logger.log(`Request ${requestId} was cancelled by the user.`);
    return res.status(200).send("Request cancelled successfully.");
  } catch (error) {
    logger.error("Error cancelling request:", error);
    return res.status(500).send("Something went wrong.");
  }
});

app.put("/drivers/:driverId/location", async (req, res) => {
  try {
    const driverId = req.params.driverId;
    const {latitude, longitude} = req.body;
    if (!latitude || !longitude) {
      return res.status(400).send("Missing latitude or longitude.");
    }
    const driverRef = db.collection("drivers").doc(driverId);
    const newLocation = new admin.firestore.GeoPoint(latitude, longitude);
    await driverRef.update({
      currentLocation: newLocation,
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.status(200).send("Location updated successfully.");
  } catch (error) {
    logger.error("Error updating driver location:", error);
    return res.status(500).send("Something went wrong updating location.");
  }
});

exports.api = onRequest({region: "asia-southeast1"}, app);


// --- Helper Function for finding a driver ---
async function findAndAssignDriverForRequest(requestDoc) {
  const requestData = requestDoc.data();
  const passengerCount = requestData.passengerCount || 1;

  const pickupPointDoc = await db.collection("pickup_points").doc(requestData.pickupPointId).get();
  if (!pickupPointDoc.exists) {
    logger.error(`[Assign] Pickup point ${requestData.pickupPointId} not found for request ${requestDoc.id}.`);
    return;
  }
  const userLocation = pickupPointDoc.data().coordinates;

  const driversSnapshot = await db.collection("drivers")
    .where("isAvailable", "==", true)
    .where("status", "==", "online")
    .get();

  if (driversSnapshot.empty) {
    logger.warn(`[Assign] No available drivers for request ${requestDoc.id}.`);
    return;
  }

  let closestDriver = null;
  let minDistance = Infinity;

  driversSnapshot.forEach((driverDoc) => {
    const driverData = driverDoc.data();
    const hasCapacity = (driverData.currentPassengers + passengerCount) <= driverData.capacity;
    if (driverData.currentLocation && hasCapacity) {
      const distance = calculateDistance(userLocation.latitude, userLocation.longitude, driverData.currentLocation.latitude, driverData.currentLocation.longitude);
      if (distance < minDistance) {
        minDistance = distance;
        closestDriver = {id: driverDoc.id, ...driverData};
      }
    }
  });

  if (closestDriver) {
    logger.log(`[Assign] Assigning request ${requestDoc.id} to driver ${closestDriver.id}.`);
    await requestDoc.ref.update({
      status: "accepted",
      driverId: closestDriver.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const newPassengerCount = closestDriver.currentPassengers + passengerCount;
    const isNowFull = newPassengerCount >= closestDriver.capacity;
    await db.collection("drivers").doc(closestDriver.id).update({
      currentPassengers: admin.firestore.FieldValue.increment(passengerCount),
      isAvailable: !isNowFull,
    });
  } else {
     logger.warn(`[Assign] Could not find a suitable driver for request ${requestDoc.id}.`);
  }
}

// --- Triggers ---

exports.findDriverForRequest = onDocumentCreated({
  document: "ride_requests/{requestId}",
  region: "asia-southeast1",
}, async (event) => {
    const requestSnapshot = event.data;
    if (!requestSnapshot || requestSnapshot.data().status !== 'pending') return;
    await findAndAssignDriverForRequest(requestSnapshot);
});

exports.handleDriverPause = onDocumentUpdated({
  document: "drivers/{driverId}",
  region: "asia-southeast1",
}, async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const driverId = event.params.driverId;
  
  if (afterData.status === "paused" && beforeData.status !== "paused") {
    logger.log(`Driver ${driverId} has paused. Handling active trips.`);
    const pauseReason = afterData.pauseReason || "Service paused";

    const requestsRef = db.collection("ride_requests");
    const snapshot = await requestsRef.where("driverId", "==", driverId).where("status", "==", "accepted").get();

    if (snapshot.empty) {
      logger.log(`No active trips to handle for paused driver ${driverId}.`);
      return;
    }

    let totalPassengersToDecrement = 0;
    const cancellationPromises = [];

    snapshot.forEach((doc) => {
      totalPassengersToDecrement += doc.data().passengerCount || 0;
      cancellationPromises.push(doc.ref.update({
        status: "cancelled_by_driver",
        cancellationReason: pauseReason,
        driverId: null,
      }));
    });

    await Promise.all(cancellationPromises);

    if (totalPassengersToDecrement > 0) {
      await db.collection("drivers").doc(driverId).update({
        currentPassengers: admin.firestore.FieldValue.increment(-totalPassengersToDecrement),
      });
    }
  }
});

exports.onDriverStatusChanged = onValueWritten({
  ref: "/driverStatus/{driverId}",
  region: "asia-southeast1",
}, async (event) => {
  const driverId = event.params.driverId;
  const statusData = event.data.after.val();

  if (!statusData) {
    return;
  }

  const isOnline = statusData.isOnline;
  const firestoreDriverRef = db.collection("drivers").doc(driverId);

  try {
      await firestoreDriverRef.update({
        status: isOnline ? "online" : "offline",
        isAvailable: isOnline,
      });
      logger.log(`Presence update: Driver ${driverId} is now ${isOnline ? "online" : "offline"}.`);
  } catch (error) {
      logger.log(`Could not update driver ${driverId} in Firestore. May not exist yet.`);
  }
});


// --- Helper Functions ---
function calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const d = R * c;
    return d;
}
function deg2rad(deg) {
  return deg * (Math.PI / 180);
}