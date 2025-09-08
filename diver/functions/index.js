const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
require('dotenv').config();

admin.initializeApp();
const db = admin.firestore();

// ใช้ Secret Manager
const gmailEmail = process.env.GMAIL_EMAIL;
const gmailPass = process.env.GMAIL_PASS;

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: { user: gmailEmail, pass: gmailPass },
});

// ✅ Trigger: เมื่อผู้ใช้ถูกสร้าง
exports.sendOtpOnUserCreated = functions.auth.user().onCreate(async (user) => {
  if (!user.email) {
    console.error("User has no email, cannot send OTP.");
    return;
  }

  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  const expires =
    admin.firestore.Timestamp.now().toMillis() + 10 * 60 * 1000;

  try {
    await db.collection("users").doc(user.uid).update({
      otp,
      otpExpires: admin.firestore.Timestamp.fromMillis(expires),
    });
  } catch (error) {
    console.error(`Failed to update user doc for ${user.uid}`, error);
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
    console.log(`OTP sent to ${user.email}`);
  } catch (error) {
    console.error("Error sending mail:", error);
  }
});

// ✅ Callable: ตรวจสอบ OTP
exports.verifyOtp = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "กรุณาเข้าสู่ระบบก่อนทำการยืนยัน"
    );
  }

  const uid = context.auth.uid;
  const userOtp = data.otp;

  if (!userOtp || typeof userOtp !== "string" || userOtp.length !== 6) {
    throw new functions.https.HttpsError("invalid-argument", "รหัส OTP ไม่ถูกต้อง");
  }

  const userDocRef = db.collection("users").doc(uid);
  const doc = await userDocRef.get();

  if (!doc.exists) {
    throw new functions.https.HttpsError("not-found", "ไม่พบข้อมูลผู้ใช้");
  }

  const storedOtp = doc.data()?.otp;
  const expires = doc.data()?.otpExpires.toMillis();

  if (storedOtp !== userOtp) {
    throw new functions.https.HttpsError("invalid-argument", "รหัส OTP ไม่ถูกต้อง");
  }

  if (Date.now() > expires) {
    throw new functions.https.HttpsError("deadline-exceeded", "รหัส OTP หมดอายุแล้ว");
  }

  await userDocRef.update({
    isVerified: true,
    otp: admin.firestore.FieldValue.delete(),
    otpExpires: admin.firestore.FieldValue.delete(),
  });

  return { success: true, message: "ยืนยันตัวตนสำเร็จ!" };
});

// firebase deploy --only functions
