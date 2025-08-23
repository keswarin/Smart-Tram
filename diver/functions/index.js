// index.js (ในโฟลเดอร์ functions)

// 1. นำเข้า Library ที่จำเป็น (ใช้ไวยากรณ์ V2 ทั้งหมด)
const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");
const logger = require("firebase-functions/logger");

// 2. ตั้งค่า Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// 3. สร้าง Express App
const app = express();
app.use(cors({ origin: true }));

// --- API จากเฟส 1 (เหมือนเดิม) ---
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
    } = req.body;

    if (!userId || !pickupBuildingId || !dropoffBuildingId) {
      return res.status(400)
          .send("Missing required fields: userId, pickupBuildingId, dropoffBuildingId");
    }

    const newRequest = {
      userId: userId,
      pickupPointId: pickupBuildingId,
      dropoffPointId: dropoffBuildingId,
      pickupPointName: pickupPointName,
      dropoffPointName: dropoffPointName,
      driverId: null,
      status: "pending",
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

app.get("/requests/pending", async (req, res) => {
  try {
    const pendingRequestsSnapshot = await db.collection("ride_requests").where("status", "==", "pending").get();
    const pendingRequests = [];
    pendingRequestsSnapshot.forEach((doc) => {
      pendingRequests.push({
        id: doc.id,
        ...doc.data(),
      });
    });
    return res.status(200).json(pendingRequests);
  } catch (error) {
    logger.error("Error fetching pending requests:", error);
    return res.status(500).send("Something went wrong fetching pending requests.");
  }
});

app.put("/requests/:requestId/accept", async (req, res) => {
  try {
    const requestId = req.params.requestId;
    const {driverId} = req.body;

    if (!driverId) {
      return res.status(400).send("Missing driverId.");
    }

    const requestRef = db.collection("ride_requests").doc(requestId);
    await requestRef.update({
      status: "accepted",
      driverId: driverId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.status(200).send("Request accepted successfully.");
  } catch (error) {
    logger.error("Error accepting request:", error);
    return res.status(500).send("Something went wrong accepting the request.");
  }
});

// 4. ส่งออก Express app (ใช้ไวยากรณ์ V2)
exports.api = onRequest({region: "asia-southeast1"}, app);


// 5. ฟังก์ชัน autoCompleteTrip (ใช้ไวยากรณ์ V2)
exports.autoCompleteTrip = onDocumentUpdated({
  document: "drivers/{driverId}",
  region: "asia-southeast1",
}, async (event) => {
  const change = event.data;
  if (!change) {
    logger.warn("No data associated with the event");
    return;
  }

  const newData = change.after.data();
  const oldData = change.before.data();
  const driverId = event.params.driverId;

  if (newData.currentLocation.latitude === oldData.currentLocation.latitude &&
    newData.currentLocation.longitude === oldData.currentLocation.longitude) {
    logger.log(`Driver ${driverId}: Location unchanged. Exiting.`);
    return;
  }

  const requestsRef = db.collection("ride_requests");
  const snapshot = await requestsRef
      .where("driverId", "==", driverId)
      .where("status", "==", "accepted")
      .limit(1)
      .get();

  if (snapshot.empty) {
    logger.log(`Driver ${driverId} has no active trip. Exiting.`);
    return;
  }

  const rideRequestDoc = snapshot.docs[0];
  const rideRequestData = rideRequestDoc.data();
  const dropoffPointId = rideRequestData.dropoffPointId;

  const dropoffPointDoc = await db.collection("pickup_points").doc(dropoffPointId).get();
  if (!dropoffPointDoc.exists) {
    logger.error(`Dropoff point ${dropoffPointId} not found.`);
    return;
  }
  const dropoffPointData = dropoffPointDoc.data();
  const dropoffLocation = dropoffPointData.coordinates;

  const driverLocation = newData.currentLocation;
  const distanceInKm = calculateDistance(
      driverLocation.latitude,
      driverLocation.longitude,
      dropoffLocation.latitude,
      dropoffLocation.longitude,
  );

  const distanceInMeters = distanceInKm * 1000;
  logger.log(`Driver ${driverId} is ${distanceInMeters.toFixed(2)} meters from destination.`);

  if (distanceInMeters <= 50) {
    logger.log(`Trip ${rideRequestDoc.id} is complete. Updating status.`);
    return rideRequestDoc.ref.update({
      status: "completed",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});

// ฟังก์ชันเสริมสำหรับคำนวณระยะทาง
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radius of the earth in km
  const dLat = deg2rad(lat2 - lat1);
  const dLon = deg2rad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const d = R * c; // Distance in km
  return d;
}

function deg2rad(deg) {
  return deg * (Math.PI / 180);
}
