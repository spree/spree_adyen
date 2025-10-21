import { Controller } from '@hotwired/stimulus'

import { AdyenCheckout, Dropin } from '@adyen/adyen-web/auto'

export default class extends Controller {
  async connect() {
    await this.initCheckout();
    this.initEventHandlers();
    if (this.dropinElement().dataset.checkoutAdyenAutoMountValue == 'true') {
      this.initDropin();
    }
  }

  dropinElement() {
    return document.getElementById('dropin-container');
  }

  async initCheckout() {
    const session = JSON.parse(this.dropinElement().dataset.checkoutAdyenCheckoutAttrubutes)
    const eventHandlers = {
      onPaymentCompleted: (result, _component) => {
        // idk why 3ds are handled here instead of paymentMethodsConfiguration.card.onPaymentCompleted
        this.redirectToPaymentSession(result);
      },
      onError: (error, component) => {
        console.error(error.name, error.message, error.stack, component);
      }
    }
    const adyenCheckout = await AdyenCheckout(Object.assign(session, eventHandlers));;
    this.adyenCheckout = adyenCheckout;
  }

  redirectToPaymentSession(result) {
    const url = new URL(this.dropinElement().dataset.checkoutAdyenPaymentSessionPathValue);
    url.searchParams.set('sessionResult', result.sessionResult);
    window.location.replace(url.href);
  }

  async initDropin() {
    const dropinConfiguration = {
      showStoredPaymentMethods: false,
      paymentMethodsConfiguration: {
        card: {
          onPaymentCompleted: (result, component) => {
            this.redirectToPaymentSession(result);
          },
          onError: (error, component) => {
            console.error(error.name, error.message, error.stack, component);
          },
          showPayButton: false,
          hasHolderName: true,
        }
      }
    };
    const dropin = new Dropin(this.adyenCheckout, dropinConfiguration)
    dropin.mount('#dropin-container');
    this.dropin = dropin;
  }

  initEventHandlers() {
    document.getElementById('checkout-payment-submit').addEventListener('click', (e) => {
      if (this.dropinElement().classList.contains('hidden')) {
        return;
      }
      e.preventDefault();
      this.dropin.submit();
    });

    document.querySelectorAll('#existing_cards input[type="radio"]').forEach(elem => elem.addEventListener("change", (e) => {
      if (e.target.dataset.show == 'dropin-container') {
        this.initDropin();
        this.dropinElement().classList.remove('hidden');
      }
      else if (this.dropin) {
        this.dropin.unmount();
        this.dropinElement().classList.add('hidden');
      }
    }))
  }
}
