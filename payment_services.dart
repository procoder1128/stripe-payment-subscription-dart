import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:openfair/model/credit_card.dart';
import 'package:openfair/net/model/chat_user.dart';
import 'package:openfair/net/model/payment_info.dart';
import 'package:openfair/providers/user.dart';
import 'package:openfair/utils/constants.dart';
import 'package:openfair/utils/utils.dart';

class StripePaymentServices {
  static createCustomer(
      User? user, AppCreditCard appCreditCard, context, userProvider) async {
    List<PaymentInfo> paymentInfos = userProvider.paymentInfos;

    try {
      final yearMonth = appCreditCard.expDate.split('/');

      final headers = {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": "Bearer " + stripeClientSecret
      };

      Uri url = Uri.parse('https://api.stripe.com/v1/tokens');
      var response = await http.post(url, headers: headers, body: {
        "card[number]": appCreditCard.cardNum,
        "card[exp_month]": yearMonth[1],
        "card[exp_year]": yearMonth[0],
        "card[cvc]": appCreditCard.ccv,
      });
      if (response.statusCode != 200) {
        await showSnackBar(context, 'Failed in getting tokens in stripe.', false);
        return;
      }
      var card_token = jsonDecode(response.body);
      PaymentInfo paymentInfo = PaymentInfo.fromJson(card_token);
      for (PaymentInfo info in paymentInfos) {
        if (info.fingerprint == paymentInfo.fingerprint) {
          await showSnackBar(
            context,
            'You are already using the card and please try another one.',
            false);
          return;
        }
      }

      url = Uri.parse('https://api.stripe.com/v1/payment_methods');
      response = await http.post(url, headers: headers, body: {
        "type": "card",
        "card[token]": card_token['id'],
      });
      if (response.statusCode != 200) {
        await showSnackBar(context, 'Failed in getting payment_methods in stripe.', false);
        return;
      }
      var pm = jsonDecode(response.body);

      ChatUser? chatUser = await userProvider.getChatUserData(user!.uid);
      url = Uri.parse('https://api.stripe.com/v1/customers');
      response = await http.post(url, headers: headers, body: {
        "description": "Openfair user to post a listing.",
        "payment_method": pm['id'],
        "invoice_settings[default_payment_method]": pm['id'],
        "email": chatUser!.email,
        "name": chatUser.fName.toString() + ' ' + chatUser.lName.toString(),
      });
      if (response.statusCode != 200) {
        await showSnackBar(context, 'Failed in getting customers in stripe.', false);
        return;
      }
      var customer = jsonDecode(response.body);
      paymentInfo.customer_id = customer['id'];
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .collection('payment_methods')
          .doc(paymentInfo.fingerprint)
          .set({
        ...paymentInfo.toJson(),
        'created_at': FieldValue.serverTimestamp(),
      });
      paymentInfos.insert(0, paymentInfo);

      Navigator.pop(context);
    } catch (e) {
      await showSnackBar(context, 'Error in createCustomer : $e', false);
      rethrow;
    }
  }

  static createGooglePayCustomer(User? user, BuildContext context, UserProvider userProvider, dynamic token) async {
    List<PaymentInfo> paymentInfos = userProvider.paymentInfos;

    try {
      final headers = {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": "Bearer " + stripeClientSecret
      };

      var card_token = jsonDecode(token);
      PaymentInfo paymentInfo = PaymentInfo(
        type: card_token["type"],
        brand: card_token["card"]["brand"],
        last4: card_token["card"]["last4"],
        customer_id: '',
        fingerprint: 'google_pay',
      );

      Uri url = Uri.parse('https://api.stripe.com/v1/payment_methods');
      var response = await http.post(url, headers: headers, body: {
        "type": "card",
        "card[token]": card_token['id'],
      });
      if (response.statusCode != 200) {
        await showSnackBar(context, 'Failed in getting payment_methods in stripe.', false);
        return;
      }
      var pm = jsonDecode(response.body);

      ChatUser? chatUser = await userProvider.getChatUserData(user!.uid);
      url = Uri.parse('https://api.stripe.com/v1/customers');
      response = await http.post(url, headers: headers, body: {
        "description": "Openfair user to post a listing.",
        "payment_method": pm['id'],
        "invoice_settings[default_payment_method]": pm['id'],
        "email": chatUser!.email,
        "name": chatUser.fName.toString() + ' ' + chatUser.lName.toString(),
      });
      if (response.statusCode != 200) {
        await showSnackBar(context, 'Failed in getting customers in stripe.', false);
        return;
      }
      var customer = jsonDecode(response.body);
      paymentInfo.customer_id = customer['id'];
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .collection('payment_methods')
          .doc(paymentInfo.fingerprint)
          .set({
        ...paymentInfo.toJson(),
        'created_at': FieldValue.serverTimestamp(),
      });
      paymentInfos.insert(0, paymentInfo);
    } catch (e) {
      await showSnackBar(context, 'Error in createCustomer : $e', false);
      rethrow;
    }
  }

  static userSubscribe(userProvider, context, int option,
      {onSuccess, onFail}) async {
    try {
      var plan_id = stripe_monthly_plan_id;
      if (option == 1) {
        plan_id = stripe_6months_plan_id;
      } else if (option == 2) {
        plan_id = stripe_yearly_plan_id;
      }

      final headers = {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": "Bearer " + stripeClientSecret
      };

      List<PaymentInfo> paymentInfos = userProvider.paymentInfos;
      if (paymentInfos.length == 0) {
        await showSnackBar(context, 'You have no payment method.', false);
        return onFail();
      }

      String strCustomerId = paymentInfos[0].customer_id.toString();
      Uri url = Uri.parse('https://api.stripe.com/v1/subscriptions');
      var response = await http.post(url, headers: headers, body: {
        "customer": strCustomerId,
        "items[0][price]": plan_id,
      });
      if (response.statusCode != 200) {
        await showSnackBar(
            context, 'Failed in getting subscriptions in stripe.', false);
        return onFail();
      }
      var res = json.decode(response.body);
      final result = {
        'id': res['id'],
        'paid_status': res['status'] == 'active',
        'cancelled': false,
        'type': option,
        'start_date': res['current_period_start'],
        'end_date': res['current_period_end'],
      };

      onSuccess(result);
    } catch (e) {
      await showSnackBar(
          context, 'Could not subscribe: ' + e.toString(), false);
      onFail();
    }
  }

  static cancelSubscription(context, String strSubscriptionId,
      {onSuccess, onFail}) async {
    try {
      final headers = {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": "Bearer " + stripeClientSecret
      };
      Uri url = Uri.parse(
          'https://api.stripe.com/v1/subscriptions/${strSubscriptionId}');
      var response = await http.delete(url, headers: headers, body: {});
      if (response.statusCode != 200) {
        await showSnackBar(
            context, 'Failed in cancelling subscriptions in stripe.', false);
        return onFail();
      }
      var res = json.decode(response.body);
      final result = {
        'id': res['id'],
        'cancelled': res['status'] == 'canceled',
      };

      onSuccess(result);
    } catch (e) {
      await showSnackBar(context,
          'Could not cancel your subscription: ' + e.toString(), false);
      onFail();
    }
  }
}
