// functions/index.js (Final Version with better comments)

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const cors = require("cors")({ origin: true });
require('dotenv').config();

admin.initializeApp();
const db = admin.firestore();

// --- Email Transporter Setup ---
// ตั้งค่าการส่งอีเมลด้วย Gmail (สำหรับระบบ OTP)
const gmailEmail = process.env.GMAIL_EMAIL;
const gmailPass = process.env.GMAIL_PASS;

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: { user: gmailEmail, pass: gmailPass },
});

// =================================================================
// AUTH FUNCTIONS (ระบบ OTP)
// =================================================================

/**
 * Triggered on new user creation to send an OTP email.
 * ทำงานเมื่อมีผู้ใช้ใหม่สมัครเข้ามาในระบบ Auth เพื่อส่ง OTP ไปยังอีเมล
 */
exports.sendOtpOnUserCreated = functions.auth.user().onCreate(async (user) => {
  if (!user.email) {
    console.error(`User ${user.uid} has no email, cannot send OTP.`);
    return;
  }
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  const expires = admin.firestore.Timestamp.now().toMillis() + 10 * 60 * 1000; // 10 minutes
  
  try {
    // บันทึก OTP และเวลาหมดอายุลงใน document ของผู้ใช้
    await db.collection("users").doc(user.uid).set({
      otp,
      otpExpires: admin.firestore.Timestamp.fromMillis(expires),
      isVerified: false, // กำหนดสถานะการยืนยันเริ่มต้น
    }, { merge: true }); // ใช้ merge เพื่อป้องกันการเขียนทับข้อมูลอื่นที่มีอยู่
  } catch (error) {
    console.error(`Failed to set OTP for user ${user.uid}`, error);
    return;
  }

  const mailOptions = {
    from: `Smart Tram <${gmailEmail}>`,
    to: user.email,
    subject: "รหัสยืนยันสำหรับ Smart Tram",
    html: `<p>รหัสยืนยันของคุณคือ: <b>${otp}</b></p><p>รหัสนี้จะหมดอายุใน 10 นาที</p>`,
  };

  try {
    await transporter.sendMail(mailOptions);
    console.log(`OTP email sent to ${user.email} for user ${user.uid}`);
  } catch (error)
  {
    console.error(`Error sending OTP email to ${user.email}:`, error);
  }
});

/**
 * A callable function for the user to verify their OTP.
 * ฟังก์ชันที่ให้แอปเรียกใช้เพื่อยืนยัน OTP ที่ผู้ใช้กรอก
 */
exports.verifyOtp = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "กรุณาเข้าสู่ระบบก่อนทำการยืนยัน");
  }
  const uid = context.auth.uid;
  const userOtp = data.otp;

  if (!userOtp || typeof userOtp !== "string" || userOtp.length !== 6) {
    throw new functions.https.HttpsError("invalid-argument", "รหัส OTP ไม่ถูกต้อง (รูปแบบผิด)");
  }

  const userDocRef = db.collection("users").doc(uid);
  const doc = await userDocRef.get();

  if (!doc.exists) {
    throw new functions.https.HttpsError("not-found", "ไม่พบข้อมูลผู้ใช้");
  }

  const { otp: storedOtp, otpExpires } = doc.data();

  if (storedOtp !== userOtp) {
    throw new functions.https.HttpsError("invalid-argument", "รหัส OTP ไม่ถูกต้อง");
  }

  if (otpExpires.toMillis() < Date.now()) {
    throw new functions.https.HttpsError("deadline-exceeded", "รหัส OTP หมดอายุแล้ว");
  }

  // ยืนยันสำเร็จ อัปเดตข้อมูลและลบ OTP ทิ้ง
  await userDocRef.update({
    isVerified: true,
    otp: admin.firestore.FieldValue.delete(),
    otpExpires: admin.firestore.FieldValue.delete(),
  });

  return { success: true, message: "ยืนยันตัวตนสำเร็จ!" };
});

// =================================================================
// RIDE REQUEST FUNCTIONS (ฟังก์ชันเกี่ยวกับคำขอเดินทาง)
// =================================================================

/**
 * Creates a new ride request.
 * Method: POST
 * Body: { userId, pickupBuildingId, dropoffBuildingId, pickupPointName, dropoffPointName, passengerCount }
 */
exports.createRequest = functions.region("asia-southeast1").https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== "POST") {
      return res.status(405).send("Method Not Allowed");
    }
    try {
      const { userId, pickupBuildingId, dropoffBuildingId, pickupPointName, dropoffPointName, passengerCount } = req.body;
      console.log("Received createRequest:", req.body);

      if (!userId || !pickupBuildingId || !dropoffBuildingId || !pickupPointName || !dropoffPointName || !passengerCount) {
        return res.status(400).send("Missing required fields.");
      }

      const pickupDoc = await db.collection('pickup_points').doc(pickupBuildingId).get();
      const dropoffDoc = await db.collection('pickup_points').doc(dropoffBuildingId).get();

      if (!pickupDoc.exists || !dropoffDoc.exists) {
        return res.status(404).send("Pickup or Dropoff point not found.");
      }

      const newRequestRef = db.collection("ride_requests").doc();
      const requestId = newRequestRef.id;

      await newRequestRef.set({
        id: requestId,
        userId,
        pickupPointId: pickupBuildingId,
        dropoffPointId: dropoffBuildingId,
        pickupPointName,
        dropoffPointName,
        pickupPoint: {
            name: pickupPointName,
            coordinates: pickupDoc.data().coordinates,
        },
        dropoffPoint: {
            name: dropoffPointName,
            coordinates: dropoffDoc.data().coordinates,
        },
        passengerCount: Number(passengerCount),
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`New ride request created: ${requestId} by user ${userId}`);
      return res.status(201).json({ id: requestId, message: "Request created successfully" });
    } catch (error) {
      console.error("Error creating request:", error);
      return res.status(500).send("Internal Server Error");
    }
  });
});

/**
 * Cancels a ride request (by user).
 * Method: POST
 * URL: /cancelRequest/{requestId}
 */
exports.cancelRequest = functions.region("asia-southeast1").https.onRequest((req, res) => {
    cors(req, res, async () => {
        if (req.method !== "POST") {
            return res.status(405).send("Method Not Allowed");
        }
        const requestId = req.path.split("/").pop();
        if (!requestId) {
            return res.status(400).send("Request ID is missing.");
        }
        try {
            const requestRef = db.collection("ride_requests").doc(requestId);
            const doc = await requestRef.get();
            if (!doc.exists) {
                return res.status(404).send("Request not found");
            }
            if (doc.data().status !== 'pending') {
                return res.status(400).send("Cannot cancel a request that is not pending.");
            }
            await requestRef.update({
                status: "cancelled_by_user",
            });
            console.log(`Request ${requestId} cancelled by user.`);
            return res.status(200).json({ message: "Request cancelled successfully" });
        } catch (error) {
            console.error(`Error cancelling request ${requestId}:`, error);
            return res.status(500).send("Internal Server Error");
        }
    });
});

// =================================================================
// DRIVER FUNCTIONS (ฟังก์ชันเกี่ยวกับคนขับ)
// =================================================================

/**
 * Updates a driver's real-time location.
 * Method: PUT
 * URL: /updateDriverLocation/{driverId}
 * Body: { latitude, longitude }
 */
exports.updateDriverLocation = functions.region("asia-southeast1").https.onRequest((req, res) => {
    cors(req, res, async () => {
        if (req.method !== "PUT") {
            return res.status(405).send("Method Not Allowed");
        }
        const driverId = req.path.split("/").pop();
        const { latitude, longitude } = req.body;
        if (!driverId) {
            return res.status(400).send("Driver ID is missing.");
        }
        if (latitude === undefined || longitude === undefined) {
            return res.status(400).send("Latitude and Longitude are required.");
        }
        try {
            const driverRef = db.collection("drivers").doc(driverId);
            await driverRef.update({
                currentLocation: new admin.firestore.GeoPoint(latitude, longitude),
                lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
            });
            return res.status(200).send({ message: "Location updated successfully" });
        } catch (error) {
            console.error(`Error updating location for driver ${driverId}:`, error);
            return res.status(500).send("Internal Server Error");
        }
    });
});

/**
 * Confirms passenger pickup and sets trip status to 'on_trip'.
 * Method: POST
 * URL: /confirmPickup/{requestId}
 */
exports.confirmPickup = functions.region("asia-southeast1").https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
      }
      const requestId = req.path.split("/").pop();
      if (!requestId) {
        return res.status(400).send("Request ID is missing.");
      }
      try {
        const requestRef = db.collection("ride_requests").doc(requestId);
        await requestRef.update({ status: "on_trip" });
        console.log(`Request ${requestId} status updated to on_trip.`);
        return res.status(200).send({ message: "Pickup confirmed" });
      } catch (error) {
        console.error(`Error confirming pickup for ${requestId}:`, error);
        return res.status(500).send("Internal Server Error");
      }
    });
});
  
/**
 * Completes a trip, updating status and freeing up driver capacity.
 * Method: POST
 * URL: /completeTrip/{requestId}
 */
exports.completeTrip = functions.region("asia-southeast1").https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
      }
      const requestId = req.path.split("/").pop();
      if (!requestId) {
        return res.status(400).send("Request ID is missing.");
      }
      try {
        const requestRef = db.collection("ride_requests").doc(requestId);
        const requestDoc = await requestRef.get();
  
        if (!requestDoc.exists) {
          return res.status(404).send("Request not found");
        }
        
        const { passengerCount = 1, driverId } = requestDoc.data();

        await requestRef.update({ status: "completed" });
        
        if (driverId) {
            const driverRef = db.collection('drivers').doc(driverId);
            // ลดจำนวนผู้โดยสารของคนขับลงตามจำนวนที่ไปส่ง
            const newPassengerCount = admin.firestore.FieldValue.increment(-passengerCount);

            await driverRef.update({
                currentPassengers: newPassengerCount,
                isAvailable: true // คนขับจะกลับมาว่างอีกครั้ง
            });
        }
  
        console.log(`Trip ${requestId} completed. Driver ${driverId} passenger count adjusted.`);
        return res.status(200).send({ message: "Trip completed" });
      } catch (error) {
        console.error(`Error completing trip for ${requestId}:`, error);
        return res.status(500).send("Internal Server Error");
      }
    });
});

// =================================================================
// FIRESTORE TRIGGERS (ทำงานอัตโนมัติเมื่อข้อมูลใน Firestore เปลี่ยน)
// =================================================================

/**
 * Triggered when a new ride_request is created. Finds and assigns an available driver.
 * ทำงานเมื่อมี ride_request ใหม่ถูกสร้างขึ้น เพื่อค้นหาและมอบหมายงานให้คนขับที่ว่าง
 */
exports.assignDriverToRequest = functions.region("asia-southeast1").firestore
    .document('ride_requests/{requestId}')
    .onCreate(async (snap, context) => {
        const requestData = snap.data();
        const requestId = context.params.requestId;
    
        if (requestData.status !== 'pending') {
            console.log(`Request ${requestId} is not pending. Aborting assignment.`);
            return null;
        }
        console.log(`Finding driver for new request: ${requestId} with ${requestData.passengerCount} passengers.`);
    
        try {
            const driversQuery = await db.collection('drivers')
                .where('status', '==', 'online')
                .where('isAvailable', '==', true)
                .get();
    
            if (driversQuery.empty) {
                console.log("No available drivers found.");
                await snap.ref.update({ status: 'no_drivers_available' });
                return null;
            }

            // ค้นหาคนขับคนแรกที่มีที่นั่งเพียงพอ
            let assignedDriverId = null;
            let assignedDriverData = null;
            for (const driverDoc of driversQuery.docs) {
                const driver = driverDoc.data();
                const currentPassengers = driver.currentPassengers || 0;
                const capacity = driver.capacity || 10;
                if ((currentPassengers + requestData.passengerCount) <= capacity) {
                    assignedDriverId = driverDoc.id;
                    assignedDriverData = driver;
                    break; 
                }
            }
    
            if (!assignedDriverId) {
                console.log("No drivers with enough capacity found.");
                await snap.ref.update({ status: 'no_drivers_available' });
                return null;
            }
    
            console.log(`Assigning driver ${assignedDriverId} to request ${requestId}`);
    
            const driverRef = db.collection('drivers').doc(assignedDriverId);
            
            // ใช้ transaction เพื่อความปลอดภัยในการอัปเดตข้อมูลพร้อมกัน
            await db.runTransaction(async (transaction) => {
                const freshDriverDoc = await transaction.get(driverRef);
                const currentPassengers = freshDriverDoc.data().currentPassengers || 0;
                const capacity = freshDriverDoc.data().capacity || 10;
                const newTotalPassengers = currentPassengers + requestData.passengerCount;

                // อัปเดตคำขอเดินทาง
                transaction.update(snap.ref, {
                    status: 'accepted',
                    driverId: assignedDriverId,
                    driverInfo: { name: assignedDriverData.displayName || 'คนขับ' }
                });

                // อัปเดตข้อมูลคนขับ
                transaction.update(driverRef, {
                    currentPassengers: newTotalPassengers,
                    isAvailable: newTotalPassengers < capacity // คนขับจะไม่ว่างถ้าผู้โดยสารเต็มความจุ
                });
            });
    
            console.log(`Assignment successful for request ${requestId} to driver ${assignedDriverId}`);
            return null;
    
        } catch (error) {
            console.error(`Error assigning driver for request ${requestId}:`, error);
            await snap.ref.update({ status: 'failed_assignment' });
            return null;
        }
});

/**
 * Triggered on driver status updates (e.g., goes offline/online).
 * This cleans up any jobs they had, preventing orphaned requests.
 * ทำงานเมื่อคนขับเปลี่ยนสถานะ (เช่น offline) เพื่อเคลียร์งานที่ค้างอยู่
 */
exports.onDriverStatusUpdate = functions.region("asia-southeast1").firestore
    .document('drivers/{driverId}')
    .onUpdate(async (change, context) => {
        const beforeData = change.before.data();
        const afterData = change.after.data();
        const driverId = context.params.driverId;

        // เช็คว่าคนขับเพิ่งจะ offline หรือหยุดพัก จากสถานะ online หรือไม่
        const wentOffline = beforeData.status === 'online' && (afterData.status === 'offline' || afterData.status === 'paused');

        if (wentOffline) {
            const reason = afterData.pauseReason || "คนขับออฟไลน์";
            console.log(`Driver ${driverId} went offline/paused. Cleaning up their active jobs.`);

            const requestsRef = db.collection('ride_requests');
            const query = requestsRef.where('driverId', '==', driverId)
                                     .where('status', 'in', ['accepted', 'on_trip']);
            
            const snapshot = await query.get();
            if (snapshot.empty) {
                console.log(`No active jobs to clean up for driver ${driverId}.`);
                return null;
            }

            // ยกเลิกงานทั้งหมดที่คนขับคนนี้รับค้างไว้
            const batch = db.batch();
            snapshot.forEach(doc => {
                console.log(`Cancelling orphaned trip ${doc.id} for driver ${driverId}`);
                batch.update(doc.ref, {
                    status: 'cancelled_by_driver',
                    cancellationReason: reason
                });
            });
            
            await batch.commit();
            console.log(`Cleanup complete for driver ${driverId}.`);
        }
        
        return null;
    });