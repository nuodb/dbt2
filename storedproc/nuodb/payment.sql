drop procedure payment if exists;

delimiter ~

CREATE PROCEDURE payment(in_w_id INT, in_d_id INT, in_c_id INT, in_c_w_id INT, in_c_d_id INT,
                         in_c_last VARCHAR(16), in_h_amount NUMERIC(18, 6))
AS

        VAR  out_w_name;
        VAR  out_w_street_1;
        VAR  out_w_street_2;
        VAR  out_w_city;
        VAR  out_w_state;
        VAR  out_w_zip;

        VAR  out_d_name;
        VAR  out_d_street_1;
        VAR  out_d_street_2;
        VAR  out_d_city;
        VAR  out_d_state;
        VAR  out_d_zip;

        VAR  out_c_id;
        VAR  out_c_first;
        VAR  out_c_middle;
        VAR  out_c_last;
        VAR  out_c_street_1;
        VAR  out_c_street_2;
        VAR  out_c_city;
        VAR  out_c_state;
        VAR  out_c_zip;
        VAR  out_c_phone;
        VAR  out_c_since;
        VAR  out_c_credit;
        VAR  out_c_credit_lim;
        VAR  out_c_discount;
        VAR  out_c_balance;
        VAR  out_c_ytd_payment;
        VAR  out_c_data;


        out_w_name, out_w_street_1, out_w_street_2, out_w_city, out_w_state, out_w_zip =
               (SELECT w_name, w_street_1, w_street_2, w_city, w_state, w_zip
               FROM warehouse
               WHERE w_id = in_w_id);

        out_d_name, out_d_street_1, out_d_street_2, out_d_city, out_d_state, out_d_zip =
               (SELECT d_name, d_street_1, d_street_2, d_city, d_state, d_zip
               FROM district
               WHERE d_id = in_d_id
                 AND d_w_id = in_w_id);

        /*
         * Pick a customer by searching for c_last, should pick the one in the
         * middle, not the first one.
         */
        IF (in_c_id = 0 )
                out_c_id = (SELECT c_id
                           FROM customer
                           WHERE c_w_id = in_c_w_id
                             AND c_d_id = in_c_d_id
                             AND c_last = in_c_last
                           ORDER BY c_first ASC limit 1);
        ELSE
                out_c_id = in_c_id;
        END_IF;

        out_c_first, out_c_middle, out_c_last, out_c_street_1, out_c_street_2, out_c_city, out_c_state, out_c_zip, out_c_phone,
        out_c_since, out_c_credit, out_c_credit_lim, out_c_discount, out_c_balance, out_c_data, out_c_ytd_payment = 
                  (SELECT c_first, c_middle, c_last, c_street_1, c_street_2, c_city,
                         c_state, c_zip, c_phone, c_since, c_credit,
                         c_credit_lim, c_discount, c_balance, c_data,
                         c_ytd_payment
                  FROM customer
                  WHERE c_w_id = in_c_w_id
                    AND c_d_id = in_c_d_id
                    AND c_id = out_c_id);

#        /* Check credit rating. */
        IF (out_c_credit = 'BC')

                out_c_data = out_c_id || ' ' || in_c_d_id || ' ' || in_c_w_id || ' ' || in_d_id || ' ' || in_w_id;

                UPDATE customer
                SET c_balance = out_c_balance - in_h_amount,
                    c_ytd_payment = out_c_ytd_payment + 1,
                    c_data = out_c_data
                WHERE c_id = out_c_id
                  AND c_w_id = in_c_w_id
                  AND c_d_id = in_c_d_id;
        ELSE
                UPDATE customer
                SET c_balance = out_c_balance - in_h_amount,
                    c_ytd_payment = out_c_ytd_payment + 1
                WHERE c_id = out_c_id
                  AND c_w_id = in_c_w_id
                  AND c_d_id = in_c_d_id;
        END_IF;

        VAR tmp_h_data = out_w_name || ' ' || out_d_name;
        INSERT INTO history (h_c_id, h_c_d_id, h_c_w_id, h_d_id, h_w_id,
                             h_date, h_amount, h_data)
        VALUES (out_c_id, in_c_d_id, in_c_w_id, in_d_id, in_w_id,
                now(), in_h_amount, tmp_h_data);

        UPDATE district
        SET d_ytd = d_ytd + in_h_amount
        WHERE d_id = in_d_id
          AND d_w_id = in_w_id;

        UPDATE warehouse
        SET w_ytd = w_ytd + in_h_amount
        WHERE w_id = in_w_id;


END_PROCEDURE~

delimiter ;

