@IsTest
private class PaymentTriggerHandlerTest {

    private static Passport_Application__c newAppWithFee(Decimal fee) {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_PAYMENT_PENDING);
        app.Fee__c = fee;
        insert app;
        return app;
    }

    private static String paymentStatusOf(Id applicationId) {
        return [
            SELECT Payment_Status__c FROM Passport_Application__c WHERE Id = :applicationId
        ].Payment_Status__c;
    }

    @IsTest
    static void testFullPaymentMarksApplicationPaid() {
        Passport_Application__c app = newAppWithFee(1500);

        Test.startTest();
        PSK_TestDataFactory.createPayment(app.Id, 1500, PSK_Constants.PAYMENT_SUCCESS);
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_PAID, paymentStatusOf(app.Id),
            'A successful payment covering the fee marks the application paid');
        System.assertNotEquals(null, [
            SELECT Payment_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Payment_Date__c, 'Going paid should stamp the payment date');
    }

    @IsTest
    static void testPartialPaymentMarksApplicationPending() {
        Passport_Application__c app = newAppWithFee(1500);

        Test.startTest();
        PSK_TestDataFactory.createPayment(app.Id, 500, PSK_Constants.PAYMENT_SUCCESS);
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_PENDING, paymentStatusOf(app.Id),
            'A part payment leaves the application pending');
    }

    @IsTest
    static void testMultiplePartialPaymentsAccumulateToPaid() {
        Passport_Application__c app = newAppWithFee(1500);

        Test.startTest();
        insert new List<Payment__c>{
            PSK_TestDataFactory.buildPayment(app.Id, 500, PSK_Constants.PAYMENT_SUCCESS),
            PSK_TestDataFactory.buildPayment(app.Id, 1000, PSK_Constants.PAYMENT_SUCCESS)
        };
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_PAID, paymentStatusOf(app.Id),
            'Two part payments that together cover the fee mark the application paid');
    }

    @IsTest
    static void testAllFailedPaymentsMarkApplicationFailed() {
        Passport_Application__c app = newAppWithFee(1500);

        Test.startTest();
        PSK_TestDataFactory.createPayment(app.Id, 1500, PSK_Constants.PAYMENT_FAILED);
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_FAILED, paymentStatusOf(app.Id),
            'When every payment attempt failed, so did the payment');
    }

    @IsTest
    static void testRefundMarksApplicationRefunded() {
        Passport_Application__c app = newAppWithFee(1500);

        Test.startTest();
        PSK_TestDataFactory.createPayment(app.Id, 1500, PSK_Constants.PAYMENT_REFUNDED);
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_REFUNDED, paymentStatusOf(app.Id));
    }

    @IsTest
    static void testUpdatingPaymentToSuccessRecalculates() {
        Passport_Application__c app = newAppWithFee(1500);
        Payment__c payment = PSK_TestDataFactory.createPayment(
            app.Id, 1500, PSK_Constants.PAYMENT_INITIATED);
        System.assertEquals(PSK_Constants.PAY_PENDING, paymentStatusOf(app.Id),
            'An initiated payment is pending, not paid');

        Test.startTest();
        payment.Status__c = PSK_Constants.PAYMENT_SUCCESS;
        update payment;
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_PAID, paymentStatusOf(app.Id),
            'Settling the payment must roll up');
    }

    @IsTest
    static void testDeletingPaymentRecalculates() {
        Passport_Application__c app = newAppWithFee(1500);
        Payment__c payment = PSK_TestDataFactory.createPayment(
            app.Id, 1500, PSK_Constants.PAYMENT_SUCCESS);
        System.assertEquals(PSK_Constants.PAY_PAID, paymentStatusOf(app.Id));

        Test.startTest();
        delete payment;
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_NOT_PAID, paymentStatusOf(app.Id),
            'Removing the only payment returns the application to Not Paid');
    }

    @IsTest
    static void testUndeletingPaymentRecalculates() {
        Passport_Application__c app = newAppWithFee(1500);
        Payment__c payment = PSK_TestDataFactory.createPayment(
            app.Id, 1500, PSK_Constants.PAYMENT_SUCCESS);
        delete payment;

        Test.startTest();
        undelete payment;
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_PAID, paymentStatusOf(app.Id),
            'Restoring the payment restores the paid state');
    }

    @IsTest
    static void testGrantedApplicationIsNeverDowngraded() {
        // Cannot_Grant_With_Pending_Payment would reject any update that moved a
        // Granting application off Paid, so the rollup must refuse to try.
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_GRANTING);
        app.Fee__c = 1500;
        insert app;

        Test.startTest();
        PSK_TestDataFactory.createPayment(app.Id, 100, PSK_Constants.PAYMENT_FAILED);
        Test.stopTest();

        System.assertEquals(PSK_Constants.PAY_PAID, paymentStatusOf(app.Id),
            'An application at Granting or beyond must stay Paid');
    }

    @IsTest
    static void testBulkPaymentsAcrossManyApplications() {
        List<Passport_Application__c> apps = new List<Passport_Application__c>();
        for (Integer i = 0; i < 40; i++) {
            Passport_Application__c app = PSK_TestDataFactory.buildApplication(
                PSK_Constants.STATUS_PAYMENT_PENDING);
            app.Fee__c = 1500;
            apps.add(app);
        }
        insert apps;

        List<Payment__c> payments = new List<Payment__c>();
        for (Passport_Application__c app : apps) {
            payments.add(PSK_TestDataFactory.buildPayment(
                app.Id, 1500, PSK_Constants.PAYMENT_SUCCESS));
        }

        Test.startTest();
        insert payments;
        Test.stopTest();

        System.assertEquals(40, [
            SELECT COUNT() FROM Passport_Application__c
            WHERE Payment_Status__c = :PSK_Constants.PAY_PAID
        ], 'All 40 parents should roll up in one pass, with no per-row DML');
    }

    @IsTest
    static void testRecalculateWithEmptyInputIsSafe() {
        PaymentTriggerHandler.recalculate(new Set<Id>());
        PaymentTriggerHandler.recalculate(null);
        // Reaching here without an exception is the assertion.
        System.assert(true, 'Empty and null inputs must be no-ops');
    }

    @IsTest
    static void testBypassSuppressesRollup() {
        Passport_Application__c app = newAppWithFee(1500);

        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Test.startTest();
        PSK_TestDataFactory.createPayment(app.Id, 1500, PSK_Constants.PAYMENT_SUCCESS);
        Test.stopTest();
        PSK_AutomationControl.reset();

        System.assertEquals(PSK_Constants.PAY_NOT_PAID, paymentStatusOf(app.Id),
            'With the bypass on, the generator owns the parent payment state');
    }
}
