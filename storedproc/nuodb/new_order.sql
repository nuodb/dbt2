drop procedure new_order if exists;

delimiter ~

CREATE PROCEDURE new_order(tmp_w_id INT,           
                           tmp_d_id INT,           
                           tmp_c_id INT,           
                           tmp_o_all_local INT,
                           tmp_o_ol_cnt INT,           
                           ol_i_id1 INT,           
                           ol_supply_w_id1 INT,           
                           ol_quantity1 INT,           
                           ol_i_id2 INT,           
                           ol_supply_w_id2 INT,           
                           ol_quantity2 INT,           
                           ol_i_id3 INT,           
                           ol_supply_w_id3 INT,           
                           ol_quantity3 INT,           
                           ol_i_id4 INT,           
                           ol_supply_w_id4 INT,           
                           ol_quantity4 INT,           
                           ol_i_id5 INT,           
                           ol_supply_w_id5 INT,           
                           ol_quantity5 INT,           
                           ol_i_id6 INT,           
                           ol_supply_w_id6 INT,           
                           ol_quantity6 INT,           
                           ol_i_id7 INT,           
                           ol_supply_w_id7 INT,           
                           ol_quantity7 INT,           
                           ol_i_id8 INT,           
                           ol_supply_w_id8 INT,           
                           ol_quantity8 INT,           
                           ol_i_id9 INT,           
                           ol_supply_w_id9 INT,           
                           ol_quantity9 INT,           
                           ol_i_id10 INT,           
                           ol_supply_w_id10 INT,           
                           ol_quantity10 INT,           
                           ol_i_id11 INT,           
                           ol_supply_w_id11 INT,           
                           ol_quantity11 INT,           
                           ol_i_id12 INT,           
                           ol_supply_w_id12 INT,           
                           ol_quantity12 INT,           
                           ol_i_id13 INT,           
                           ol_supply_w_id13 INT,           
                           ol_quantity13 INT,           
                           ol_i_id14 INT,           
                           ol_supply_w_id14 INT,           
                           ol_quantity14 INT,           
                           ol_i_id15 INT,           
                           ol_supply_w_id15 INT,           
                           ol_quantity15 INT)
                              
AS

  VAR out_c_credit;
  VAR tmp_i_name;
  VAR tmp_i_data;
  VAR out_c_last;

  VAR tmp_ol_supply_w_id;
  VAR tmp_ol_quantity int;
  VAR out_d_next_o_id;
  VAR tmp_i_id int;

  VAR tmp_s_quantity int;

  VAR out_w_tax;
  VAR out_d_tax;
  VAR out_c_discount;
  VAR tmp_i_price real;
  VAR tmp_ol_amount real;
  VAR tmp_total_amount real;

  VAR o_id;

  o_id = 0;

  out_w_tax = (SELECT w_tax
               FROM warehouse
               WHERE w_id = tmp_w_id);

  -- ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  -- Commented out a standard way of order id allocations, instead
  -- using sequence.
  --
  -- out_d_tax, out_d_next_o_id = (SELECT d_tax, d_next_o_id
  --                               FROM district   
  --                               WHERE d_w_id = tmp_w_id
  --                               AND d_id = tmp_d_id FOR UPDATE);

  -- o_id=out_d_next_o_id;

  -- UPDATE district
  -- SET d_next_o_id = d_next_o_id + 1
  -- WHERE d_w_id = tmp_w_id
  --   AND d_id = tmp_d_id;

  out_d_tax, out_d_next_o_id = (SELECT d_tax, (next value for order_seq) as d_next_o_id
                                FROM district   
                                WHERE d_w_id = tmp_w_id
                                AND d_id = tmp_d_id);

  o_id=out_d_next_o_id;
  
  out_c_discount, out_c_last, out_c_credit = (SELECT c_discount , c_last, c_credit
                                             FROM customer
                                             WHERE c_w_id = tmp_w_id
                                               AND c_d_id = tmp_d_id
                                               AND c_id = tmp_c_id);

  INSERT INTO new_order (no_o_id, no_d_id, no_w_id)
  VALUES (out_d_next_o_id, tmp_d_id, tmp_w_id);

  INSERT INTO orders (o_id, o_d_id, o_w_id, o_c_id, o_entry_d,
                       o_carrier_id, o_ol_cnt, o_all_local)
  VALUES (out_d_next_o_id, tmp_d_id, tmp_w_id, tmp_c_id,
           now(), NULL, tmp_o_ol_cnt, tmp_o_all_local);

  tmp_total_amount = 0;

  VAR counter int = 0;
  WHILE (counter < 15)
    IF (tmp_o_ol_cnt > counter )

      tmp_i_id = CASE counter 
                    WHEN 0 THEN ol_i_id1
                    WHEN 1 THEN ol_i_id2
                    WHEN 2 THEN ol_i_id3
                    WHEN 3 THEN ol_i_id4
                    WHEN 4 THEN ol_i_id5
                    WHEN 5 THEN ol_i_id6
                    WHEN 6 THEN ol_i_id7
                    WHEN 7 THEN ol_i_id8
                    WHEN 8 THEN ol_i_id9
                    WHEN 9 THEN ol_i_id10
                    WHEN 10 THEN ol_i_id11
                    WHEN 11 THEN ol_i_id12
                    WHEN 12 THEN ol_i_id13
                    WHEN 13 THEN ol_i_id14
                    WHEN 14 THEN ol_i_id15
                 END;
      tmp_ol_supply_w_id = CASE counter 
                    WHEN 0 THEN ol_supply_w_id1
                    WHEN 1 THEN ol_supply_w_id2
                    WHEN 2 THEN ol_supply_w_id3
                    WHEN 3 THEN ol_supply_w_id4
                    WHEN 4 THEN ol_supply_w_id5
                    WHEN 5 THEN ol_supply_w_id6
                    WHEN 6 THEN ol_supply_w_id7
                    WHEN 7 THEN ol_supply_w_id8
                    WHEN 8 THEN ol_supply_w_id9
                    WHEN 9 THEN ol_supply_w_id10
                    WHEN 10 THEN ol_supply_w_id11
                    WHEN 11 THEN ol_supply_w_id12
                    WHEN 12 THEN ol_supply_w_id13
                    WHEN 13 THEN ol_supply_w_id14
                    WHEN 14 THEN ol_supply_w_id15
                 END;
      tmp_ol_quantity = CASE counter
                    WHEN 0 THEN ol_quantity1
                    WHEN 1 THEN ol_quantity2
                    WHEN 2 THEN ol_quantity3
                    WHEN 3 THEN ol_quantity4
                    WHEN 4 THEN ol_quantity5
                    WHEN 5 THEN ol_quantity6
                    WHEN 6 THEN ol_quantity7
                    WHEN 7 THEN ol_quantity8
                    WHEN 8 THEN ol_quantity9
                    WHEN 9 THEN ol_quantity10
                    WHEN 10 THEN ol_quantity11
                    WHEN 11 THEN ol_quantity12
                    WHEN 12 THEN ol_quantity13
                    WHEN 13 THEN ol_quantity14
                    WHEN 14 THEN ol_quantity15
                 END;

      tmp_i_price, tmp_i_name, tmp_i_data = (SELECT i_price, i_name, i_data
                                            FROM item
                                            WHERE i_id = tmp_i_id);

      IF (tmp_i_price > 0 )
         tmp_ol_amount = tmp_i_price * tmp_ol_quantity;

         call new_order_2(tmp_w_id, tmp_d_id, tmp_i_id,
                          tmp_ol_quantity, tmp_i_price,
                          tmp_i_name, tmp_i_data,
                          out_d_next_o_id, tmp_ol_amount,
                          tmp_ol_supply_w_id, counter + 1, tmp_s_quantity);
         tmp_total_amount = tmp_total_amount + tmp_ol_amount;
      END_IF;
    ELSE
      BREAK;
    END_IF;
    counter = counter + 1;
  END_WHILE;

END_PROCEDURE~

delimiter ;

