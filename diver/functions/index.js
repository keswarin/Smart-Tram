// index.js (ในโฟลเดอร์ functions)

const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentUpdated, onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");
const logger = require("firebase-functions/logger");

admin.initializeApp();
const db = admin.firestore();

const app = express();
app.use(cors({ origin: true }));

// --- API (ไม่มีการเปลี่ยนแปลง) ---
// ... (โค้ด API ทั้ง 5 ตัวของคุณยังคงอยู่ที่นี่) ...
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

exports.api = onRequest({region: "asia-southeast1"}, app);


// --- ฟังก์ชันอัตโนมัติ ---

exports.autoCompleteTrip = onDocumentUpdated({
  document: "drivers/{driverId}",
  region: "asia-southeast1",
}, async (event) => {
  // ... (โค้ดส่วนนี้เหมือนเดิมทุกประการ) ...
  const change = event.data;
  if (!change) return;

  const newData = change.after.data();
  const oldData = change.before.data();
  const driverId = event.params.driverId;

  if (newData.currentLocation.latitude === oldData.currentLocation.latitude &&
      newData.currentLocation.longitude === oldData.currentLocation.longitude) {
    return;
  }

  const requestsRef = db.collection("ride_requests");
  const snapshot = await requestsRef.where("driverId", "==", driverId).where("status", "==", "accepted").get();

  if (snapshot.empty) return;

  for (const rideRequestDoc of snapshot.docs) {
    const rideRequestData = rideRequestDoc.data();
    const dropoffPointId = rideRequestData.dropoffPointId;

    const dropoffPointDoc = await db.collection("pickup_points").doc(dropoffPointId).get();
    if (!dropoffPointDoc.exists) continue;

    const dropoffLocation = dropoffPointDoc.data().coordinates;
    const driverLocation = newData.currentLocation;
    const distanceInMeters = calculateDistance(driverLocation.latitude, driverLocation.longitude, dropoffLocation.latitude, dropoffLocation.longitude) * 1000;

    if (distanceInMeters <= 50) {
      logger.log(`Trip ${rideRequestDoc.id} is complete.`);
      const passengerCount = rideRequestData.passengerCount || 1;

      await db.collection("drivers").doc(driverId).update({
        isAvailable: true,
        currentPassengers: admin.firestore.FieldValue.increment(-passengerCount),
      });

      await rideRequestDoc.ref.update({
        status: "completed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
});

exports.findDriverForRequest = onDocumentCreated({
  document: "ride_requests/{requestId}",
  region: "asia-southeast1",
}, async (event) => {
  // ... (โค้ดส่วนนี้เหมือนเดิมทุกประการ) ...
  const requestSnapshot = event.data;
  if (!requestSnapshot) return;

  const requestData = requestSnapshot.data();
  const passengerCount = requestData.passengerCount || 1;

  const pickupPointDoc = await db.collection("pickup_points").doc(requestData.pickupPointId).get();
  if (!pickupPointDoc.exists) return;

  const userLocation = pickupPointDoc.data().coordinates;

  const driversSnapshot = await db.collection("drivers").where("isAvailable", "==", true).where("status", "==", "online").get();
  if (driversSnapshot.empty) {
    logger.warn("No available drivers.");
    return;
  }

  let closestDriver = null;
  let minDistance = Infinity;

  driversSnapshot.forEach((driverDoc) => {
    const driverData = driverDoc.data();
    const hasCapacity = (driverData.currentPassengers + passengerCount) <= driverData.capacity;

    if (driverData.currentLocation && hasCapacity) {
      const distance = calculateDistance(
          userLocation.latitude, userLocation.longitude,
          driverData.currentLocation.latitude, driverData.currentLocation.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestDriver = {id: driverDoc.id, ...driverData};
      }
    }
  });

  if (closestDriver) {
    logger.log(`Assigning request to driver ${closestDriver.id}.`);

    await requestSnapshot.ref.update({
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
    logger.warn("Could not find a suitable driver (no capacity or too far).");
  }
});

// --- 🎯 ฟังก์ชันใหม่: จัดการงานเมื่อคนขับหยุดพัก ---
exports.reassignPausedDriverTrips = onDocumentUpdated({
  document: "drivers/{driverId}",
  region: "asia-southeast1",
}, async (event) => {
  const change = event.data;
  if (!change) return;

  const newData = change.after.data();
  const oldData = change.before.data();
  const driverId = event.params.driverId;

  // ทำงานเฉพาะเมื่อสถานะเปลี่ยนเป็น "paused"
  if (newData.status === "paused" && oldData.status === "online") {
    logger.log(`Driver ${driverId} paused service. Reassigning trips.`);

    // 1. ค้นหางานทั้งหมดที่คนขับคนนี้กำลังทำอยู่
    const requestsRef = db.collection("ride_requests");
    const snapshot = await requestsRef
        .where("driverId", "==", driverId)
        .where("status", "==", "accepted")
        .get();

    if (snapshot.empty) {
      logger.log(`No active trips to reassign for driver ${driverId}.`);
      return;
    }

    // 2. รีเซ็ตงานทั้งหมดกลับไปที่สถานะ "pending"
    const reassignPromises = [];
    let totalPassengersToDecrement = 0;

    snapshot.forEach((doc) => {
      const requestData = doc.data();
      totalPassengersToDecrement += requestData.passengerCount || 1;

      const promise = doc.ref.update({
        status: "pending",
        driverId: null, // ลบคนขับเก่าออก
      });
      reassignPromises.push(promise);
    });
    
    // รอให้การรีเซ็ตงานทั้งหมดเสร็จสิ้น
    await Promise.all(reassignPromises);

    // 3. อัปเดตสถานะของคนขับที่หยุดงาน
    await db.collection("drivers").doc(driverId).update({
      isAvailable: false, // ทำให้ไม่ว่างทันที
      currentPassengers: admin.firestore.FieldValue.increment(-totalPassengersToDecrement),
    });

    logger.log(`Reassigned ${snapshot.size} trips from driver ${driverId}.`);
  }
});


// ฟังก์ชันเสริมสำหรับคำนวณระยะทาง
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
