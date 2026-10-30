(def nil? (lambda (v) (= v nil)))

(def list (lambda () ...))
(def list? (lambda (v) (= "list" (typeof v))))

(def symbol? (lambda (v) (= "symbol" (typeof v))))

(def defracro (racro (name args body) (def name (racro args body))))

(def defn-codegen (lambda (name args body)
  (list def name
    (list lambda args
      (cond
        (nil? body) nil
        (nil? (cdr body)) (car body)
        (cons do body))))))
(defracro defn (name args) (eval (defn-codegen 'name 'args '...)))

(defn intersperse (e xs)
  (cond (nil? xs) nil
        (nil? (cdr xs)) xs
        (cons (car xs) (cons e (intersperse e (cdr xs))))))

(defn not (v) (= v false))

(defracro or () (eval (cons cond (intersperse true '...))))

(defn and-codegen (operands)
  (cond (nil? operands) true
        (list cond (car operands) (and-codegen (cdr operands)) false)))
(defracro and () (eval (and-codegen '...)))

(defn map (f xs)
  (cond (nil? xs) nil
        (cons (f (car xs)) (map f (cdr xs)))))

(defn filter (f xs)
  (cond (nil? xs) nil
        (f (car xs)) (cons (car xs) (filter f (cdr xs)))
        (filter f (cdr xs))))

(defn reduce (f acc xs)
  (cond (nil? xs) acc
        (reduce f (f acc (car xs)) (cdr xs))))
(def foldl reduce)

(def inc (lambda (v) (+ v 1)))
(def dec (lambda (v) (- v 1)))

(def range
  (lambda (from to)
          (cond (> from to) nil
                (cons from (range (+ 1 from) to)))))

(def take
  (lambda (n lst)
          (cond (<= n 0) nil
          (nil? lst) nil
          (cons (car lst) (take (- n 1) (cdr lst))))))

(def drop
  (lambda (n lst)
          (cond (<= n 0) lst
          (nil? lst) nil
          (drop (- n 1) (cdr lst)))))

(defn t () (print "#t") true)
(defn f () (print "#f") false)
