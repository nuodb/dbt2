drop procedure new_order_2 if exists ;

delimiter ~

CREATE PROCEDURE new_order_2 (in_w_id INT,
	                      in_d_id INT,
	                      in_ol_i_id INT,
	                      in_ol_quantity INT,
	                      in_i_price NUMERIC(18, 6),
	                      in_i_name TEXT,
	                      in_i_data TEXT,
	                      in_ol_o_id INT,
	                      in_ol_amount NUMERIC(18, 6),
	                      in_ol_supply_w_id INT,
	                      in_ol_number INT,
                          out out_s_quantity INT)

AS

        VAR	tmp_s_dist; 
        VAR	tmp_s_data;

	out_s_quantity, tmp_s_dist, tmp_s_data = 
             (SELECT s_quantity, 
		CASE (in_d_id) 
                  WHEN 1 THEN s_dist_01
                  WHEN 2 THEN s_dist_02
                  WHEN 3 THEN s_dist_03
                  WHEN 4 THEN s_dist_04
                  WHEN 5 THEN s_dist_05
                  WHEN 6 THEN s_dist_06
                  WHEN 7 THEN s_dist_07
                  WHEN 8 THEN s_dist_08
                  WHEN 9 THEN s_dist_09
                  WHEN 10 THEN s_dist_10
                END ,
		s_data
		FROM stock
		WHERE s_i_id = in_ol_i_id
		  AND s_w_id = in_w_id);

	IF (out_s_quantity > in_ol_quantity + 10 )
		UPDATE stock
		SET s_quantity = s_quantity - in_ol_quantity
		WHERE s_i_id = in_ol_i_id
		  AND s_w_id = in_w_id;
	ELSE
		UPDATE stock
		SET s_quantity = s_quantity - in_ol_quantity + 91
		WHERE s_i_id = in_ol_i_id
		  AND s_w_id = in_w_id;
	END_IF;

	INSERT INTO order_line (ol_o_id, ol_d_id, ol_w_id, ol_number, ol_i_id,
	                        ol_supply_w_id, ol_delivery_d, ol_quantity,
                                ol_amount, ol_dist_info)
	VALUES (in_ol_o_id, in_d_id, in_w_id, in_ol_number, in_ol_i_id,
	        in_ol_supply_w_id, NULL, in_ol_quantity, in_ol_amount,
	        tmp_s_dist);
END_PROCEDURE~

delimiter ;

