# Android Integration Guide for spree_adyen

This guide provides step-by-step instructions for integrating Adyen Android Drop-in with spree_adyen using session flow and Drop-In component.

## Resources

- [Official Adyen Documentation for Android integration](https://docs.adyen.com/online-payments/build-your-integration/sessions-flow/?platform=Android&integration=Drop-in&version=5.13.1)
- [Spree Adyen API docs]()
- [Offcial Adyen example for Android integration](https://github.com/adyen-examples/adyen-android-online-payments)

## Overview

The integration consists of two main components:
- **Spree Adyen**: Provides API for your client and receive payment result from Adyen
- **Your Android client app**: Shows the Drop-in UI and handles payment flow

## Step 1: Import the library

Import the compatibility module:

import the module with Jet Compose
```
implementation "com.adyen.checkout:drop-in-compose:YOUR_VERSION"
```

import without Jet Compose
```
implementation "com.adyen.checkout:drop-in:YOUR_VERSION"
```

## Step 2: Create a checkout session

create session model from spree_adyen API `POST /api/v2/storefront/adyen/payment_sessions` or `GET POST /api/v2/storefront/adyen/payment_sessions/{id}` endpoint:
(see API docs for more details)

```
val sessionModel = SessionModel.SERIALIZER.deserialize(sessionsResponseJSON)
```

sessionsResponseJSON should contain:
- `sessionData` - available as `adyen_data` in spree_adyen API response
- `id` - available as `adyen_id` in spree_adyen API response


## Step 3

call `CheckoutSessionProvider.createSession` passing serialized session data (`sessionModel`) and `dropInConfiguration`

dropingConfiguration example:

```
val checkoutConfiguration = CheckoutConfiguration(
	    environment = environment,
	    clientKey = clientKey,
	    shopperLocale = shopperLocale, // Optional
	) {
	    // Optional: add Drop-in configuration.
	    dropIn {
	        setEnableRemovingStoredPaymentMethods(true)
	    }
	 
	    // Optional: add or change default configuration for the card payment method.
	    card {
	        setHolderNameRequired(true)
	        setShopperReference("...")
	    }
	 
	    // Optional: change configuration for 3D Secure 2.
	    adyen3DS2 {
	        setThreeDSRequestorAppURL("...")
	    }
	}
```
see also: https://docs.adyen.com/online-payments/build-your-integration/sessions-flow/?platform=Web&integration=Drop-in&version=6.18.1#create-instance


`environment` - enum: `live` or `test`
`clientKey` - `client_key` from payment_sessions endpoint
`shopperLocale` - shopper locale in ISO format


```
	// Create an object for the checkout session.
	val result = CheckoutSessionProvider.createSession(sessionModel, dropInConfiguration)
	 
	// If the payment session is successful, handle the result.
	// If the payment session encounters an error, handle the error.
	when (result) {
	    is CheckoutSessionResult.Success -> handleCheckoutSession(result.checkoutSession)
	    is CheckoutSessionResult.Error -> handleError(result.exception)
	}
```

## Step 4: Launch and show Drop-in

```
	override fun onDropInResult(sessionDropInResult: SessionDropInResult?) {
	   when (sessionDropInResult) {
	      // The payment finishes with a result.
	      is SessionDropInResult.Finished -> handleResult(sessionDropInResult.result)
	      // The shopper dismisses Drop-in.
	      is SessionDropInResult.CancelledByUser ->
	      // Drop-in encounters an error.
	      is SessionDropInResult.Error -> handleError(sessionDropInResult.reason)
	      // Drop-in encounters an unexpected state.
	      null ->
	   }
	}
```

## Step 5: Create the Drop-in launcher

DropIn.startPayment, passing:
- dropInLauncher - The Drop-in launcher object
- checkoutSession - result of `CheckoutSessionProvider.createSession`
- dropInConfiguration - Your Drop-in configuration

Example:
```
	import com.adyen.checkout.dropin.compose.startPayment
	import com.adyen.checkout.dropin.compose.rememberLauncherForDropInResult
	 
	@Composable
	private fun ComposableDropIn() {
	    val dropInLauncher = rememberLauncherForDropInResult(sessionDropInCallback)
	 
	    DropIn.startPayment(dropInLauncher, checkoutSession, dropInConfiguration)
	}
```

# Get payment outcome

The are two possible ways to achieve this at the moment:

or just:
1. Wait for backend to process the payment
2. Continue shopping experience

## 1. Wait for backend to process the payment

backend will change the state of `payment_session` to one of the following state

- pending - chosen payment method can take a while to complete 
- completed - payment resulted in success, order has been completed
- canceled - payment canceled
- refused - payment failed